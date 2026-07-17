from flask import Flask, jsonify, render_template, request, send_file
import csv
import datetime as dt
import io
import math
import os
import random
import re
from typing import Any, Dict, Iterable, List, Optional, Tuple

import requests
from influxdb import InfluxDBClient

from reportlab.graphics.shapes import Circle, Drawing, PolyLine, Rect, String
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


app = Flask(__name__)


@app.after_request
def add_security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    if request.path.startswith("/api/"):
        response.headers["Cache-Control"] = "private, no-store"
    return response


# Runtime configuration. Credentials are injected by Kubernetes and never stored
# in this repository.
INFLUXDB_HOST = os.environ.get("INFLUXDB_HOST", "garmin-influxdb.garmin.svc.cluster.local")
INFLUXDB_PORT = int(os.environ.get("INFLUXDB_PORT", "8086"))
INFLUXDB_DB = os.environ.get("INFLUXDB_DATABASE", "GarminStats")
INFLUXDB_USER = os.environ.get("INFLUXDB_USERNAME", "")
INFLUXDB_PASS = os.environ.get("INFLUXDB_PASSWORD", "")
VM_URL = os.environ.get(
    "VM_URL", "http://victoriametrics.ring-health.svc.cluster.local:8428"
).rstrip("/")
RING_DEVICE = os.environ.get("RING_DEVICE", "colmi_r02")
if not re.fullmatch(r"[A-Za-z0-9_.:-]+", RING_DEVICE):
    raise RuntimeError("RING_DEVICE contains unsupported characters")
MOCK_DATA_ENV = os.environ.get("MOCK_DATA", "false").lower() == "true"
DB_TIMEOUT = float(os.environ.get("DB_TIMEOUT_SECONDS", "5"))

UTC = dt.timezone.utc


class DataSourceError(RuntimeError):
    """Raised when a production data source cannot be read."""

    def __init__(self, source: str, message: str):
        super().__init__(message)
        self.source = source


# ==============================================================================
# Date, value, and query helpers
# ==============================================================================


def parse_month(month_value: Optional[str]) -> Tuple[int, int]:
    """Parse YYYY-MM and reject invalid or future months."""
    value = month_value or dt.date.today().strftime("%Y-%m")
    try:
        year, month = (int(part) for part in value.split("-"))
        start = dt.date(year, month, 1)
    except (TypeError, ValueError):
        raise ValueError("month must use YYYY-MM format")

    today = dt.date.today()
    if start > dt.date(today.year, today.month, 1):
        raise ValueError("future months are not available")
    return year, month


def month_bounds(year: int, month: int) -> Tuple[dt.date, dt.date]:
    start = dt.date(year, month, 1)
    if month == 12:
        next_month = dt.date(year + 1, 1, 1)
    else:
        next_month = dt.date(year, month + 1, 1)
    end = next_month - dt.timedelta(days=1)

    today = dt.date.today()
    if year == today.year and month == today.month:
        end = min(end, today)
    return start, end


def as_number(value: Any) -> Optional[float]:
    if value is None or value == "":
        return None
    try:
        number = float(value)
        if not math.isfinite(number):
            return None
        return number
    except (TypeError, ValueError):
        return None


def as_int(value: Any) -> Optional[int]:
    number = as_number(value)
    return int(number) if number is not None else None


def average(values: Iterable[Any]) -> Optional[float]:
    numbers = [as_number(value) for value in values]
    numbers = [value for value in numbers if value is not None]
    return sum(numbers) / len(numbers) if numbers else None


def influx_point_date(point: Dict[str, Any]) -> Optional[dt.date]:
    timestamp = point.get("time")
    if not timestamp:
        return None
    try:
        return dt.datetime.fromisoformat(timestamp.replace("Z", "+00:00")).date()
    except ValueError:
        try:
            return dt.datetime.strptime(timestamp[:10], "%Y-%m-%d").date()
        except ValueError:
            return None


def calculate_recovery(
    sleep_score: Optional[float], hrv: Optional[float], stress: Optional[float]
) -> Optional[int]:
    # A readiness score is only reported when all inputs used by the formula
    # are real measurements. This prevents fabricated scores in production.
    if sleep_score is None or hrv is None or stress is None:
        return None
    score = 0.4 * sleep_score + 0.4 * (hrv * 1.3) + 0.2 * (100 - stress)
    return min(100, max(20, int(score)))


def vm_query_range(
    expression: str, start: dt.date, end: dt.date
) -> Dict[dt.date, float]:
    start_timestamp = int(
        dt.datetime.combine(start, dt.time.min, tzinfo=UTC).timestamp()
    )
    end_timestamp = int(
        dt.datetime.combine(end, dt.time.max, tzinfo=UTC).timestamp()
    )

    response = requests.get(
        f"{VM_URL}/api/v1/query_range",
        params={
            "query": expression,
            "start": start_timestamp,
            "end": end_timestamp,
            "step": 86400,
        },
        timeout=DB_TIMEOUT,
    )
    response.raise_for_status()
    payload = response.json()
    if payload.get("status") != "success":
        raise DataSourceError(f"VictoriaMetrics query failed for {expression}")

    result = payload.get("data", {}).get("result", [])
    by_day: Dict[dt.date, List[float]] = {}
    for series in result:
        for timestamp, value in series.get("values", []):
            number = as_number(value)
            if number is None:
                continue
            day = dt.datetime.fromtimestamp(float(timestamp), tz=UTC).date()
            by_day.setdefault(day, []).append(number)

    return {day: sum(values) / len(values) for day, values in by_day.items()}


# ==============================================================================
# Data access
# ==============================================================================


def get_db_data(year: int, month: int) -> Tuple[List[Dict[str, Any]], bool]:
    """Read real data, or explicitly generate mock data when MOCK_DATA=true.

    Production mode never silently changes to mock data. A database outage is
    returned as an error so operators cannot mistake demo telemetry for health
    data.
    """
    if MOCK_DATA_ENV:
        return generate_mock_data(year, month), True

    try:
        influx_client = InfluxDBClient(
            host=INFLUXDB_HOST,
            port=INFLUXDB_PORT,
            username=INFLUXDB_USER,
            password=INFLUXDB_PASS,
            database=INFLUXDB_DB,
            timeout=DB_TIMEOUT,
        )
        influx_client.ping()
    except Exception as exc:
        app.logger.exception("InfluxDB connection failed: host=%s database=%s", INFLUXDB_HOST, INFLUXDB_DB)
        raise DataSourceError("influxdb", "InfluxDB is unavailable") from exc

    try:
        vm_test = requests.get(f"{VM_URL}/api/v1/status/tsdb", timeout=DB_TIMEOUT)
        vm_test.raise_for_status()
    except Exception as exc:
        app.logger.exception("VictoriaMetrics connection failed: url=%s", VM_URL)
        raise DataSourceError("victoriametrics", "VictoriaMetrics is unavailable") from exc

    try:
        return fetch_and_merge_production_data(influx_client, year, month), False
    except Exception as exc:
        app.logger.exception("Production data merge failed")
        raise DataSourceError("data-query", "Production data query failed") from exc


def fetch_and_merge_production_data(
    influx_client: InfluxDBClient, year: int, month: int
) -> List[Dict[str, Any]]:
    start_date, end_date = month_bounds(year, month)
    data: List[Dict[str, Any]] = []

    influx_start = f"{start_date.isoformat()}T00:00:00Z"
    influx_end = f"{end_date.isoformat()}T23:59:59Z"

    sleep_query = (
        "SELECT avgOvernightHrv, sleepDuration, sleepScore FROM SleepSummary "
        f"WHERE time >= '{influx_start}' AND time <= '{influx_end}'"
    )
    daily_query = (
        "SELECT totalSteps, restingHeartRate, activeMinutes, caloriesBurned "
        "FROM DailyStats "
        f"WHERE time >= '{influx_start}' AND time <= '{influx_end}'"
    )
    # duration is an InfluxQL keyword, so quote ActivitySummary field names.
    # Quoting all selected fields also protects this query if another field name
    # becomes reserved in a future InfluxDB version.
    workout_query = (
        'SELECT "type", "duration", "calories", "distance", "name" FROM ActivitySummary '
        f"WHERE time >= '{influx_start}' AND time <= '{influx_end}'"
    )

    sleep_results = list(influx_client.query(sleep_query).get_points())
    daily_results = list(influx_client.query(daily_query).get_points())
    workout_results = list(influx_client.query(workout_query).get_points())

    garmin_sleep: Dict[dt.date, Dict[str, Any]] = {}
    for point in sleep_results:
        day = influx_point_date(point)
        if day:
            garmin_sleep[day] = point

    garmin_daily: Dict[dt.date, Dict[str, Any]] = {}
    for point in daily_results:
        day = influx_point_date(point)
        if day:
            garmin_daily[day] = point

    garmin_workouts: Dict[dt.date, List[Dict[str, Any]]] = {}
    for point in workout_results:
        day = influx_point_date(point)
        if day:
            garmin_workouts.setdefault(day, []).append(point)

    device_selector = f'{{device="{RING_DEVICE}"}}'
    metric_expressions = {
        "hrv": f"avg_over_time(biometric_hrv_rmssd{device_selector}[24h])",
        "hr": f"avg_over_time(biometric_hr_bpm{device_selector}[24h])",
        "spo2": f"avg_over_time(biometric_spo2_pct{device_selector}[24h])",
        "stress": f"avg_over_time(biometric_stress{device_selector}[24h])",
        "battery": f"last_over_time(ring_battery_pct{device_selector}[24h])",
    }
    vm_data: Dict[str, Dict[dt.date, float]] = {}
    for key, expression in metric_expressions.items():
        try:
            vm_data[key] = vm_query_range(expression, start_date, end_date)
        except Exception:
            # One missing Ring metric must not turn real Garmin data into mock
            # data. Keep the metric empty and expose the absence as null values.
            app.logger.exception("VictoriaMetrics metric query failed: %s", key)
            vm_data[key] = {}

    current_day = start_date
    while current_day <= end_date:
        sleep_point = garmin_sleep.get(current_day, {})
        daily_point = garmin_daily.get(current_day, {})
        workouts_points = garmin_workouts.get(current_day, [])

        ring_hrv = vm_data.get("hrv", {}).get(current_day)
        ring_hr = vm_data.get("hr", {}).get(current_day)
        ring_spo2 = vm_data.get("spo2", {}).get(current_day)
        ring_stress = vm_data.get("stress", {}).get(current_day)
        ring_battery = vm_data.get("battery", {}).get(current_day)

        sleep_score = as_number(sleep_point.get("sleepScore"))
        garmin_hrv = as_number(sleep_point.get("avgOvernightHrv"))
        hrv = garmin_hrv if garmin_hrv is not None else ring_hrv
        resting_hr = as_number(daily_point.get("restingHeartRate"))
        if resting_hr is None:
            resting_hr = ring_hr

        steps = as_int(daily_point.get("totalSteps"))
        calories = as_int(daily_point.get("caloriesBurned"))
        active_minutes = as_int(daily_point.get("activeMinutes"))
        sleep_duration_minutes = as_number(sleep_point.get("sleepDuration"))
        sleep_duration = (
            round(sleep_duration_minutes / 60, 1)
            if sleep_duration_minutes is not None
            else None
        )

        workouts = []
        for workout in workouts_points:
            workout_time = workout.get("time")
            workouts.append(
                {
                    "type": workout.get("type") or "Workout",
                    "name": workout.get("name") or "General Session",
                    "duration": (
                        int(as_number(workout.get("duration")) / 60)
                        if as_number(workout.get("duration")) is not None
                        else 0
                    ),
                    "calories": as_int(workout.get("calories")) or 0,
                    "distance": (
                        round(as_number(workout.get("distance")) / 1000, 2)
                        if as_number(workout.get("distance")) is not None
                        else None
                    ),
                    "time": workout_time[11:16]
                    if isinstance(workout_time, str) and len(workout_time) >= 16
                    else "",
                }
            )

        has_data = bool(
            sleep_point
            or daily_point
            or workouts_points
            or any(value is not None for value in (ring_hrv, ring_hr, ring_spo2, ring_stress, ring_battery))
        )
        recovery = calculate_recovery(sleep_score, hrv, ring_stress)
        sleep_quality = (
            "Good"
            if sleep_score is not None and sleep_score > 80
            else "Fair"
            if sleep_score is not None and sleep_score > 65
            else "Poor"
            if sleep_score is not None
            else None
        )

        data.append(
            {
                "date": current_day.isoformat(),
                "day": current_day.day,
                "has_data": has_data,
                "data_status": "real" if has_data else "no-data",
                "recovery_score": recovery,
                "current_hr": as_int(ring_hr),
                "resting_hr": as_int(resting_hr),
                "hrv": as_int(hrv),
                "sleep_duration": sleep_duration,
                "sleep_quality": sleep_quality,
                "sleep_score": as_int(sleep_score),
                "stress": as_int(ring_stress),
                "spo2": as_int(ring_spo2),
                "steps": steps,
                "calories": calories,
                "distance": round(steps * 0.00076, 1) if steps is not None else None,
                "active_minutes": active_minutes,
                "workouts": workouts,
                "ring_battery": as_int(ring_battery),
                "last_sync": "Available" if has_data else None,
            }
        )
        current_day += dt.timedelta(days=1)

    return data


def generate_mock_data(year: int, month: int) -> List[Dict[str, Any]]:
    """Generate deterministic data only when MOCK_DATA=true is explicit."""
    rng = random.Random(year * 100 + month)
    start_date, end_date = month_bounds(year, month)
    data = []

    base_hrv = 45 + rng.randint(0, 15)
    base_rhr = 54 + rng.randint(0, 8)
    base_sleep = 7.2

    current_day = start_date
    while current_day <= end_date:
        dow = current_day.weekday()
        weekend_factor = 1.2 if dow >= 5 else 1.0
        fluctuation = rng.uniform(-1.5, 1.5)
        sleep_duration = max(4.5, min(10.0, base_sleep * weekend_factor + fluctuation))
        sleep_score = min(100, max(35, int(sleep_duration * 10 + rng.randint(-8, 8))))
        hrv = int(base_hrv + rng.randint(-12, 12) + (sleep_score - 70) * 0.3)
        resting_hr = int(base_rhr + rng.randint(-5, 6) - (sleep_score - 70) * 0.1)
        stress = min(85, max(12, int(32 - (sleep_score - 70) * 0.4 + rng.randint(-8, 8))))
        recovery = min(100, max(25, int(0.3 * sleep_score + 0.5 * hrv + 0.2 * (100 - stress))))
        steps = int(7500 * (1.3 if dow == 5 else 0.8 if dow == 6 else 1.0) + rng.randint(-1500, 3000))
        calories = int(2000 + steps * 0.05 + rng.randint(-100, 200))

        workouts = []
        if current_day.day % 3 == 0:
            workout_type = rng.choice(["Running", "Cycling", "Swimming"])
            names = {
                "Running": "Morning Tempo Run",
                "Cycling": "Homelab Commute Route",
                "Swimming": "Active Recovery Laps",
            }
            duration = rng.randint(25, 75)
            distance = (
                round(duration * 0.2, 1)
                if workout_type == "Running"
                else round(duration * 0.4, 1)
                if workout_type == "Cycling"
                else None
            )
            workouts.append(
                {
                    "type": workout_type,
                    "name": names[workout_type],
                    "duration": duration,
                    "calories": int(duration * 8.5),
                    "distance": distance,
                    "time": f"0{rng.randint(7, 9)}:30",
                }
            )

        data.append(
            {
                "date": current_day.isoformat(),
                "day": current_day.day,
                "has_data": True,
                "data_status": "mock",
                "recovery_score": recovery,
                "current_hr": resting_hr + rng.randint(15, 30),
                "resting_hr": resting_hr,
                "hrv": hrv,
                "sleep_duration": round(sleep_duration, 1),
                "sleep_quality": "Good" if sleep_score > 78 else "Fair" if sleep_score > 60 else "Poor",
                "sleep_score": sleep_score,
                "stress": stress,
                "spo2": rng.choice([97, 98, 99]),
                "steps": steps,
                "calories": calories,
                "distance": round(steps * 0.00076, 1),
                "active_minutes": int(steps / 200 + rng.randint(-5, 15)),
                "workouts": workouts,
                "ring_battery": max(10, 100 - (current_day.day % 6) * 15),
                "last_sync": "Demo data",
            }
        )
        current_day += dt.timedelta(days=1)

    return data


# ==============================================================================
# Narrative and reporting helpers
# ==============================================================================


def values_for(rows: Iterable[Dict[str, Any]], key: str) -> List[float]:
    return [value for value in (as_number(row.get(key)) for row in rows) if value is not None]


def generate_weekly_narrative(daily_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    last_7 = daily_data[-7:]
    all_recovery = values_for(daily_data, "recovery_score")
    all_sleep = values_for(daily_data, "sleep_score")
    all_hrv = values_for(daily_data, "hrv")
    all_rhr = values_for(daily_data, "resting_hr")

    if not all_recovery and not all_sleep and not all_hrv:
        return {
            "score": None,
            "evaluation": "No data",
            "sleep_insights": "No sleep data is available for this period.",
            "recovery_insights": "No recovery or HRV data is available for this period.",
            "workout_insights": "No workout data is available for this period.",
            "stress_insights": "No stress or SpO₂ data is available for this period.",
            "achievements": "No achievements can be calculated without real measurements.",
            "focus": "Sync Garmin and Ring data before interpreting this report.",
        }

    avg_recovery_base = average(all_recovery)
    avg_sleep_base = average(all_sleep)
    avg_hrv_base = average(all_hrv)
    avg_rhr_base = average(all_rhr)

    weekly_sleep = values_for(last_7, "sleep_score")
    weekly_duration = values_for(last_7, "sleep_duration")
    weekly_recovery = values_for(last_7, "recovery_score")
    weekly_hrv = values_for(last_7, "hrv")
    weekly_rhr = values_for(last_7, "resting_hr")
    weekly_stress = values_for(last_7, "stress")
    weekly_spo2 = values_for(last_7, "spo2")

    avg_weekly_recovery = average(weekly_recovery)
    avg_weekly_sleep = average(weekly_sleep)
    avg_weekly_duration = average(weekly_duration)
    avg_weekly_hrv = average(weekly_hrv)
    avg_weekly_rhr = average(weekly_rhr)
    avg_weekly_stress = average(weekly_stress)
    avg_weekly_spo2 = average(weekly_spo2)

    if avg_weekly_duration is None or avg_weekly_sleep is None:
        sleep_insights = "Sleep data is incomplete for the last seven days."
    else:
        sleep_insights = f"You slept an average of {avg_weekly_duration:.1f} hours per night (Sleep Score: {avg_weekly_sleep:.0f}). "
        if avg_sleep_base is not None and avg_weekly_sleep >= avg_sleep_base + 3:
            sleep_insights += "This is higher than the monthly average."
        elif avg_sleep_base is not None and avg_weekly_sleep <= avg_sleep_base - 3:
            debt = max(0, 7.5 * len(weekly_duration) - sum(weekly_duration))
            sleep_insights += f"This is below the monthly baseline. Estimated sleep debt is {debt:.1f} hours."
        else:
            sleep_insights += "Sleep patterns are consistent with the available monthly data."

    if avg_weekly_recovery is None or avg_weekly_hrv is None or avg_hrv_base is None:
        recovery_insights = "Recovery and HRV data is incomplete for the last seven days."
    elif avg_weekly_hrv > avg_hrv_base + 4:
        recovery_insights = f"Readiness averaged {avg_weekly_recovery:.0f}; HRV averaged {avg_weekly_hrv:.0f} ms, above the monthly baseline of {avg_hrv_base:.0f} ms."
    elif avg_weekly_hrv < avg_hrv_base - 4:
        recovery_insights = f"Readiness averaged {avg_weekly_recovery:.0f}; HRV averaged {avg_weekly_hrv:.0f} ms, below the monthly baseline of {avg_hrv_base:.0f} ms."
    else:
        recovery_insights = f"Readiness averaged {avg_weekly_recovery:.0f}; HRV averaged {avg_weekly_hrv:.0f} ms and is stable against the monthly baseline."

    total_workouts = sum(len(day.get("workouts", [])) for day in last_7)
    workout_insights = f"You logged {total_workouts} workouts in the available seven-day period."
    if total_workouts == 0:
        workout_insights += " No formal workouts were logged."

    if avg_weekly_stress is None or avg_weekly_spo2 is None:
        stress_insights = "Stress and SpO₂ data is incomplete for the last seven days."
    else:
        stress_insights = f"Stress averaged {avg_weekly_stress:.0f}/100 and SpO₂ averaged {avg_weekly_spo2:.1f}%."

    achievements = []
    step_values = values_for(last_7, "steps")
    if step_values and max(step_values) > 12000:
        achievements.append("👑 Step Champion: logged a day exceeding 12,000 steps.")
    if weekly_rhr and avg_rhr_base is not None and min(weekly_rhr) < avg_rhr_base - 3:
        achievements.append(f"❤️ Heart Health: resting heart rate low of {min(weekly_rhr):.0f} bpm.")
    if avg_weekly_recovery is not None and avg_weekly_recovery >= 80:
        achievements.append("⚡ Supercharged: weekly readiness averaged above 80%.")
    if not achievements:
        achievements.append("🌱 Consistent: available biometric data was processed without gaps in the selected period.")

    if avg_weekly_hrv is not None and avg_hrv_base is not None and avg_weekly_hrv < avg_hrv_base - 3:
        focus = "Focus on active recovery and sleep."
    elif avg_weekly_sleep is not None and avg_weekly_sleep < 65:
        focus = "Focus on sleep consistency and sleep hygiene."
    elif total_workouts < 2:
        focus = "Focus on adding two moderate cardio sessions next week."
    else:
        focus = "Focus on maintaining the current routine and increasing training gradually."

    return {
        "score": int(avg_weekly_recovery) if avg_weekly_recovery is not None else None,
        "evaluation": (
            "Optimal"
            if avg_weekly_recovery is not None and avg_weekly_recovery >= 75
            else "Balanced"
            if avg_weekly_recovery is not None and avg_weekly_recovery >= 60
            else "Fatigued"
            if avg_weekly_recovery is not None
            else "No data"
        ),
        "sleep_insights": sleep_insights,
        "recovery_insights": recovery_insights,
        "workout_insights": workout_insights,
        "stress_insights": stress_insights,
        "achievements": "<br>".join(achievements),
        "focus": focus,
    }


def comparison_metrics(current: List[Dict[str, Any]], previous: List[Dict[str, Any]]) -> List[Dict[str, str]]:
    definitions = [
        ("Readiness Score", "recovery_score", "avg"),
        ("Resting Heart Rate (bpm)", "resting_hr", "avg"),
        ("Heart Rate Variability (ms)", "hrv", "avg"),
        ("Sleep Duration (hrs)", "sleep_duration", "avg"),
        ("Total Step Count", "steps", "sum"),
        ("Active Minutes", "active_minutes", "sum"),
    ]
    metrics = []
    for label, key, operation in definitions:
        current_values = values_for(current, key)
        previous_values = values_for(previous, key)
        current_value = (
            sum(current_values) / len(current_values)
            if operation == "avg" and current_values
            else sum(current_values)
            if current_values
            else None
        )
        previous_value = (
            sum(previous_values) / len(previous_values)
            if operation == "avg" and previous_values
            else sum(previous_values)
            if previous_values
            else None
        )

        diff = current_value - previous_value if current_value is not None and previous_value is not None else None
        if current_value is None:
            current_text = "N/A"
        elif key == "sleep_duration":
            current_text = f"{current_value:.1f}h"
        elif operation == "sum":
            current_text = f"{int(current_value):,}"
        else:
            current_text = f"{current_value:.0f}"

        if previous_value is None:
            previous_text = "N/A"
        elif key == "sleep_duration":
            previous_text = f"{previous_value:.1f}h"
        elif operation == "sum":
            previous_text = f"{int(previous_value):,}"
        else:
            previous_text = f"{previous_value:.0f}"

        if diff is None:
            diff_text, direction = "N/A", "flat"
        elif key == "sleep_duration":
            diff_text, direction = f"{'+' if diff >= 0 else ''}{diff:.1f}h", "up" if diff > 0 else "down" if diff < 0 else "flat"
        elif operation == "sum":
            diff_text, direction = f"{'+' if diff >= 0 else ''}{int(diff):,}", "up" if diff > 0 else "down" if diff < 0 else "flat"
        else:
            diff_text, direction = f"{'+' if diff >= 0 else ''}{diff:.0f}", "up" if diff > 0 else "down" if diff < 0 else "flat"

        metrics.append({"name": label, "current": current_text, "previous": previous_text, "diff": diff_text, "direction": direction})
    return metrics


# ==============================================================================
# Flask endpoints
# ==============================================================================


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/healthz")
def healthz():
    return jsonify({"status": "healthy"})


@app.route("/api/health")
def api_health():
    try:
        year, month = parse_month(request.args.get("month"))
        daily_data, is_mocked = get_db_data(year, month)
        previous_year = year if month > 1 else year - 1
        previous_month = month - 1 if month > 1 else 12
        previous_data, _ = get_db_data(previous_year, previous_month)
    except ValueError as exc:
        return jsonify({"status": "invalid_request", "error": str(exc)}), 400
    except DataSourceError as exc:
        return jsonify({"status": "data_unavailable", "mocked": False, "source": exc.source, "error": str(exc)}), 503

    populated = [day for day in daily_data if day.get("has_data")]
    latest = populated[-1].copy() if populated else {}
    if latest and len(populated) > 1:
        yesterday = populated[-2]
        for result_key, source_key in (
            ("recovery_change", "recovery_score"),
            ("hr_change", "resting_hr"),
            ("hrv_change", "hrv"),
            ("sleep_change", "sleep_score"),
        ):
            current = as_number(latest.get(source_key))
            previous = as_number(yesterday.get(source_key))
            latest[result_key] = int(current - previous) if current is not None and previous is not None else None

    chart_data = daily_data[-14:]
    charts = {
        "labels": [f"Day {day['day']}" for day in chart_data],
        "recovery": [day.get("recovery_score") for day in chart_data],
        "sleep_duration": [day.get("sleep_duration") for day in chart_data],
        "sleep_score": [day.get("sleep_score") for day in chart_data],
        "hrv": [day.get("hrv") for day in chart_data],
        "resting_hr": [day.get("resting_hr") for day in chart_data],
    }

    recovery_days = [day for day in daily_data if day.get("recovery_score") is not None]
    if recovery_days:
        best_day = max(recovery_days, key=lambda day: day["recovery_score"])
        worst_day = min(recovery_days, key=lambda day: day["recovery_score"])
        trends_summary = (
            f"Peak recovery occurred on Day {best_day['day']} with a readiness score of "
            f"{best_day['recovery_score']}%, while the lowest recovery was on Day "
            f"{worst_day['day']} ({worst_day['recovery_score']}%)."
        )
    else:
        trends_summary = "No recovery measurements are available for this month."

    return jsonify(
        {
            "status": "ok" if populated else "no_data",
            "mocked": is_mocked,
            "daily": latest,
            "charts": charts,
            "weekly": generate_weekly_narrative(daily_data),
            "monthly": {
                "trends_summary": trends_summary,
                "suggested_goals": "Use the available measurements to set gradual sleep and activity goals. This dashboard is not medical advice.",
                "metrics": comparison_metrics(daily_data, previous_data),
            },
        }
    )


@app.route("/api/report/regenerate", methods=["POST"])
def api_regenerate():
    return jsonify({"status": "ok", "message": "The next request will read the current database values."})


@app.route("/api/report/export")
def api_export():
    try:
        year, month = parse_month(request.args.get("month"))
        export_format = request.args.get("format", "json").lower()
        if export_format not in {"csv", "json"}:
            raise ValueError("format must be csv or json")
        daily_data, _ = get_db_data(year, month)
    except ValueError as exc:
        return jsonify({"status": "invalid_request", "error": str(exc)}), 400
    except DataSourceError as exc:
        return jsonify({"status": "data_unavailable", "mocked": False, "source": exc.source, "error": str(exc)}), 503

    if export_format == "json":
        return jsonify(daily_data)

    output = io.StringIO()
    fields = [
        "date", "day", "data_status", "recovery_score", "resting_hr", "hrv",
        "sleep_duration", "sleep_score", "stress", "spo2", "steps", "calories",
        "active_minutes",
    ]
    writer = csv.DictWriter(output, fieldnames=fields)
    writer.writeheader()
    for day in daily_data:
        writer.writerow({field: day.get(field) for field in fields})

    binary_output = io.BytesIO(output.getvalue().encode("utf-8"))
    return send_file(
        binary_output,
        mimetype="text/csv",
        as_attachment=True,
        download_name=f"health_report_{year:04d}-{month:02d}.csv",
    )


@app.route("/api/report/download")
def api_download_pdf():
    try:
        year, month = parse_month(request.args.get("month"))
        daily_data, is_mocked = get_db_data(year, month)
    except ValueError as exc:
        return jsonify({"status": "invalid_request", "error": str(exc)}), 400
    except DataSourceError as exc:
        return jsonify({"status": "data_unavailable", "mocked": False, "source": exc.source, "error": str(exc)}), 503

    populated = [day for day in daily_data if day.get("has_data")]
    if not populated:
        return jsonify({"status": "no_data", "error": "no measurements are available for this month"}), 404

    weekly_narrative = generate_weekly_narrative(daily_data)
    avg_recovery = average(day.get("recovery_score") for day in populated)
    avg_sleep = average(day.get("sleep_score") for day in populated)
    avg_hrv = average(day.get("hrv") for day in populated)
    avg_rhr = average(day.get("resting_hr") for day in populated)
    total_steps = sum(values_for(populated, "steps"))
    total_cals = sum(values_for(populated, "calories"))

    buffer = io.BytesIO()
    document = SimpleDocTemplate(buffer, pagesize=letter, rightMargin=40, leftMargin=40, topMargin=40, bottomMargin=40)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("TitleStyle", parent=styles["Normal"], fontName="Helvetica-Bold", fontSize=24, leading=28, textColor=colors.HexColor("#0f172a"), spaceAfter=6)
    subtitle_style = ParagraphStyle("SubtitleStyle", parent=styles["Normal"], fontSize=11, textColor=colors.HexColor("#64748b"), spaceAfter=20)
    heading_style = ParagraphStyle("HeadingStyle", parent=styles["Normal"], fontName="Helvetica-Bold", fontSize=15, leading=18, textColor=colors.HexColor("#1e40af"), spaceBefore=14, spaceAfter=8)
    body_style = ParagraphStyle("BodyStyle", parent=styles["Normal"], fontSize=9.5, leading=13.5, textColor=colors.HexColor("#334155"), spaceAfter=10)
    header_style = ParagraphStyle("HeaderStyle", parent=styles["Normal"], fontName="Helvetica-Bold", fontSize=9, textColor=colors.white)
    cell_style = ParagraphStyle("CellStyle", parent=styles["Normal"], fontSize=9, textColor=colors.HexColor("#334155"))

    def display(value: Optional[float], suffix: str = "") -> str:
        return f"{value:.0f}{suffix}" if value is not None else "N/A"

    story = [
        Paragraph("Health & Recovery Report", title_style),
        Paragraph(
            f"Month: {year:04d}-{month:02d} | Generated: {dt.date.today().isoformat()} | "
            f"Data status: {'Demo Mode' if is_mocked else 'Verified Homelab Dataset'}",
            subtitle_style,
        ),
    ]

    summary_data = [
        [Paragraph("Monthly Readiness", header_style), Paragraph("Sleep Score", header_style), Paragraph("Resting HR", header_style), Paragraph("HRV", header_style)],
        [Paragraph(display(avg_recovery, "%"), cell_style), Paragraph(display(avg_sleep, "/100"), cell_style), Paragraph(display(avg_rhr, " bpm"), cell_style), Paragraph(display(avg_hrv, " ms"), cell_style)],
    ]
    summary_table = Table(summary_data, colWidths=[130, 130, 130, 130])
    summary_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1e3a8a")),
        ("BACKGROUND", (0, 1), (-1, 1), colors.HexColor("#f8fafc")),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#cbd5e1")),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.extend([summary_table, Spacer(1, 15), Paragraph("Readiness / Recovery Trend", heading_style)])

    plot_data = [day for day in daily_data[-14:] if day.get("recovery_score") is not None]
    drawing = Drawing(520, 130)
    drawing.add(Rect(0, 0, 520, 130, fillColor=colors.HexColor("#f8fafc"), strokeColor=colors.HexColor("#e2e8f0"), strokeWidth=1))
    for grid_y in [25, 50, 75, 100]:
        canvas_y = 15 + grid_y
        drawing.add(PolyLine([(0, canvas_y), (520, canvas_y)], strokeColor=colors.HexColor("#cbd5e1"), strokeWidth=0.5))
        drawing.add(String(5, canvas_y + 2, str(grid_y), fontSize=7, fillColor=colors.HexColor("#64748b")))
    if plot_data:
        x_step = 520.0 / (len(plot_data) - 1) if len(plot_data) > 1 else 520.0
        points = []
        for index, day in enumerate(plot_data):
            x = index * x_step
            y = 15 + (day["recovery_score"] / 100.0) * 100
            points.append((x, y))
            drawing.add(Circle(x, y, 3, fillColor=colors.HexColor("#3b82f6"), strokeColor=colors.white, strokeWidth=0.5))
            drawing.add(String(x + 2, 4, f"D{day['day']}", fontSize=6.5, fillColor=colors.HexColor("#64748b")))
        if len(points) > 1:
            drawing.add(PolyLine(points, strokeColor=colors.HexColor("#3b82f6"), strokeWidth=2))
    else:
        drawing.add(String(200, 65, "No recovery measurements", fontSize=10, fillColor=colors.HexColor("#64748b")))
    story.extend([drawing, Spacer(1, 15), Paragraph("Weekly Narrative Summary", heading_style)])

    narrative = (
        f"<b>Weekly Health Score:</b> {weekly_narrative.get('score') or 'N/A'} "
        f"({weekly_narrative.get('evaluation', 'No data')})<br/><br/>"
        f"<b>Sleep:</b> {weekly_narrative['sleep_insights']}<br/><br/>"
        f"<b>Recovery and HRV:</b> {weekly_narrative['recovery_insights']}<br/><br/>"
        f"<b>Workouts:</b> {weekly_narrative['workout_insights']}<br/><br/>"
        f"<b>Stress and oxygen:</b> {weekly_narrative['stress_insights']}<br/><br/>"
        f"<b>Suggested focus:</b> {weekly_narrative['focus']}"
    )
    story.extend([Paragraph(narrative, body_style), Spacer(1, 15), Paragraph("Monthly Totals", heading_style)])
    story.append(Paragraph(
        f"Total steps: <b>{int(total_steps):,}</b><br/>"
        f"Total calories: <b>{int(total_cals):,} kcal</b><br/>"
        f"Average resting HR: <b>{display(avg_rhr, ' bpm')}</b><br/>"
        f"Average HRV: <b>{display(avg_hrv, ' ms')}</b>",
        body_style,
    ))

    document.build(story)
    buffer.seek(0)
    return send_file(buffer, mimetype="application/pdf", as_attachment=True, download_name=f"health_report_{year:04d}-{month:02d}.pdf")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)

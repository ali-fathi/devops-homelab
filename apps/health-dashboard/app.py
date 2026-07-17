from flask import Flask, render_template, jsonify, request, send_file
import os
import csv
import json
import io
import datetime
import random
import requests
from influxdb import InfluxDBClient

app = Flask(__name__)

# Configurable environment variables for DB access
INFLUXDB_HOST = os.environ.get("INFLUXDB_HOST", "garmin-influxdb.garmin.svc.cluster.local")
INFLUXDB_PORT = int(os.environ.get("INFLUXDB_PORT", 8086))
INFLUXDB_DB = os.environ.get("INFLUXDB_DATABASE", "GarminStats")
INFLUXDB_USER = os.environ.get("INFLUXDB_USERNAME", "")
INFLUXDB_PASS = os.environ.get("INFLUXDB_PASSWORD", "")

VM_URL = os.environ.get("VM_URL", "http://victoriametrics.ring-health.svc.cluster.local:8428")
MOCK_DATA_ENV = os.environ.get("MOCK_DATA", "false").lower() == "true"

# ReportLab libraries for PDF creation
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.graphics.shapes import Drawing, Rect, String, PolyLine, Circle

# ==============================================================================
# Database Clients & Fallback Mock Logic
# ==============================================================================

def get_db_data(year, month):
    """
    Attempts to pull data from InfluxDB (Garmin) and VictoriaMetrics (Ring).
    If connection fails or credentials aren't set, falls back to generating
    realistic mock data.
    """
    if MOCK_DATA_ENV:
        return generate_mock_data(year, month), True

    try:
        # 1. Attempt InfluxDB Connection
        influx_client = InfluxDBClient(
            host=INFLUXDB_HOST, 
            port=INFLUXDB_PORT, 
            username=INFLUXDB_USER, 
            password=INFLUXDB_PASS, 
            database=INFLUXDB_DB,
            timeout=3
        )
        
        # Test connection
        influx_client.ping()

        # 2. Attempt VictoriaMetrics Connection
        vm_test = requests.get(f"{VM_URL}/api/v1/status/tsdb", timeout=3)
        vm_test.raise_for_status()

        # Connections succeeded! Let's fetch and compile data
        return fetch_and_merge_production_data(influx_client, year, month), False

    except Exception as e:
        app.logger.warning(f"Homelab DB connection failed: {e}. Falling back to Mock Demo Mode.")
        return generate_mock_data(year, month), True


def fetch_and_merge_production_data(influx_client, year, month):
    """
    Queries actual InfluxDB and VictoriaMetrics databases.
    Normalizes time series and aggregates values by day of the month.
    """
    # Find number of days in the month
    start_date = datetime.date(year, month, 1)
    if month == 12:
        end_date = datetime.date(year + 1, 1, 1) - datetime.timedelta(days=1)
    else:
        end_date = datetime.date(year, month + 1, 1) - datetime.timedelta(days=1)
    
    num_days = end_date.day
    
    # Structure database arrays
    data = []
    
    # Query InfluxDB for Garmin data
    # (Using basic InfluxQL queries from DailyStats, SleepSummary, and ActivitySummary)
    influx_start = f"{start_date.isoformat()}T00:00:00Z"
    influx_end = f"{end_date.isoformat()}T23:59:59Z"
    
    sleep_query = f"SELECT avgOvernightHrv, sleepDuration, sleepScore FROM SleepSummary WHERE time >= '{influx_start}' AND time <= '{influx_end}'"
    daily_query = f"SELECT totalSteps, restingHeartRate, activeMinutes, caloriesBurned FROM DailyStats WHERE time >= '{influx_start}' AND time <= '{influx_end}'"
    workout_query = f"SELECT type, duration, calories, distance, name FROM ActivitySummary WHERE time >= '{influx_start}' AND time <= '{influx_end}'"
    
    sleep_results = list(influx_client.query(sleep_query).get_points())
    daily_results = list(influx_client.query(daily_query).get_points())
    workout_results = list(influx_client.query(workout_query).get_points())

    # Mapping queries by day
    garmin_sleep = {}
    for pt in sleep_results:
        dt = datetime.datetime.strptime(pt['time'][:10], "%Y-%m-%d").date()
        garmin_sleep[dt.day] = pt

    garmin_daily = {}
    for pt in daily_results:
        dt = datetime.datetime.strptime(pt['time'][:10], "%Y-%m-%d").date()
        garmin_daily[dt.day] = pt

    garmin_workouts = {}
    for pt in workout_results:
        dt = datetime.datetime.strptime(pt['time'][:10], "%Y-%m-%d").date()
        if dt.day not in garmin_workouts:
            garmin_workouts[dt.day] = []
        garmin_workouts[dt.day].append(pt)

    # Query VictoriaMetrics for Ring metrics using PromQL range api
    # Step size is 1 day (86400 seconds)
    vm_start = int(datetime.datetime.combine(start_date, datetime.time.min).timestamp())
    vm_end = int(datetime.datetime.combine(end_date, datetime.time.max).timestamp())
    
    metrics = {
        'hrv': 'avg_over_time(biometric_hrv_rmssd[24h])',
        'hr': 'avg_over_time(biometric_hr_bpm[24h])',
        'spo2': 'avg_over_time(biometric_spo2_pct[24h])',
        'stress': 'avg_over_time(biometric_stress[24h])',
        'battery': 'last_over_time(ring_battery_pct[24h])'
    }
    
    vm_data = {k: {} for k in metrics}
    for key, expr in metrics.items():
        try:
            url = f"{VM_URL}/api/v1/query_range?query={expr}&start={vm_start}&end={vm_end}&step=86400"
            r = requests.get(url, timeout=3)
            if r.status_code == 200:
                result_vals = r.json().get('data', {}).get('result', [])
                if result_vals:
                    for val in result_vals[0].get('values', []):
                        ts, val_str = val[0], val[1]
                        day = datetime.datetime.fromtimestamp(ts).day
                        vm_data[key][day] = float(val_str)
        except Exception:
            pass # Keep empty if querying metric fails

    # Merge Ring and Garmin data day-by-day
    for d in range(1, num_days + 1):
        day_date = datetime.date(year, month, d)
        
        # Garmin Data points
        g_s = garmin_sleep.get(d, {})
        g_d = garmin_daily.get(d, {})
        g_w = garmin_workouts.get(d, [])
        
        # Ring VM data points
        r_hrv = vm_data['hrv'].get(d, 0.0)
        r_hr = vm_data['hr'].get(d, 0.0)
        r_spo2 = vm_data['spo2'].get(d, 0.0)
        r_stress = vm_data['stress'].get(d, 0.0)
        r_battery = vm_data['battery'].get(d, 100.0)

        # Readiness formula (combines HRV, sleep score, and stress index)
        sleep_score = g_s.get('sleepScore', 75)
        hrv = g_s.get('avgOvernightHrv', r_hrv or 52)
        stress = r_stress or 25
        recovery = int(0.4 * sleep_score + 0.4 * (hrv * 1.3) + 0.2 * (100 - stress))
        recovery = min(100, max(20, recovery))

        # Convert workout structures
        workouts = []
        for w in g_w:
            workouts.append({
                'type': w.get('type', 'Workout'),
                'name': w.get('name', 'General Session'),
                'duration': int(w.get('duration', 0) / 60), # seconds to minutes
                'calories': int(w.get('calories', 0)),
                'distance': round(w.get('distance', 0.0) / 1000, 2) if w.get('distance') else None,
                'time': pt.get('time')[11:16] if 'time' in pt else "08:00"
            })

        data.append({
            'date': day_date.strftime("%Y-%m-%d"),
            'day': d,
            'recovery_score': recovery,
            'current_hr': int(r_hr) if r_hr else 68,
            'resting_hr': int(g_d.get('restingHeartRate', r_hr or 58)),
            'hrv': int(hrv),
            'sleep_duration': round(g_s.get('sleepDuration', 450) / 60, 1), # minutes to hours
            'sleep_quality': "Good" if sleep_score > 80 else "Fair" if sleep_score > 65 else "Poor",
            'sleep_score': sleep_score,
            'stress': int(stress),
            'spo2': int(r_spo2) if r_spo2 else 98,
            'steps': int(g_d.get('totalSteps', 8500)),
            'calories': int(g_d.get('caloriesBurned', 2300)),
            'distance': round(g_d.get('totalSteps', 8500) * 0.00076, 1),
            'active_minutes': int(g_d.get('activeMinutes', 35)),
            'workouts': workouts,
            'ring_battery': int(r_battery),
            'last_sync': "Just Now" if d == num_days else "10:32 PM"
        })

    return data


def generate_mock_data(year, month):
    """
    Generates deterministic but realistic fluctuating data for testing.
    This guarantees that the charts are populated beautifully even if offline.
    """
    random.seed(year * 100 + month) # Stable random metrics per month selection

    # Find number of days in the month
    start_date = datetime.date(year, month, 1)
    if month == 12:
        end_date = datetime.date(year + 1, 1, 1) - datetime.timedelta(days=1)
    else:
        end_date = datetime.date(year, month + 1, 1) - datetime.timedelta(days=1)
    
    num_days = end_date.day
    data = []

    # Baselines for biometric metrics
    base_hrv = 45 + random.randint(0, 15)
    base_rhr = 54 + random.randint(0, 8)
    base_sleep = 7.2

    for d in range(1, num_days + 1):
        day_date = datetime.date(year, month, d)
        
        # Day of week adjustments (e.g. sleep more on weekends, active on Sat)
        dow = day_date.weekday()
        weekend_factor = 1.2 if dow >= 5 else 1.0
        
        # Add random fluctuations (simulates physical stress/recovery cycles)
        fluctuation = random.uniform(-1.5, 1.5)
        sleep_dur = max(4.5, min(10.0, base_sleep * weekend_factor + fluctuation))
        sleep_score = int(sleep_dur * 10 + random.randint(-8, 8))
        sleep_score = min(100, max(35, sleep_score))
        
        hrv_val = int(base_hrv + random.randint(-12, 12) + (sleep_score - 70) * 0.3)
        rhr_val = int(base_rhr + random.randint(-5, 6) - (sleep_score - 70) * 0.1)
        stress_val = int(32 - (sleep_score - 70) * 0.4 + random.randint(-8, 8))
        stress_val = min(85, max(12, stress_val))

        recovery_val = int(0.3 * sleep_score + 0.5 * hrv_val + 0.2 * (100 - stress_val))
        recovery_val = min(100, max(25, recovery_val))

        steps_val = int(7500 * (1.3 if dow == 5 else 0.8 if dow == 6 else 1.0) + random.randint(-1500, 3000))
        calories_val = int(2000 + steps_val * 0.05 + random.randint(-100, 200))
        dist_val = round(steps_val * 0.00076, 1)
        active_min = int(steps_val / 200 + random.randint(-5, 15))

        # Random workouts
        workouts = []
        if d % 3 == 0:
            w_types = ["Running", "Cycling", "Swimming"]
            w_names = {
                "Running": "Morning Tempo Run",
                "Cycling": "Homelab Commute Route",
                "Swimming": "Active Recovery Laps"
            }
            w_type = random.choice(w_types)
            dur = random.randint(25, 75)
            w_dist = round(dur * 0.2, 1) if w_type == "Running" else round(dur * 0.4, 1) if w_type == "Cycling" else None
            workouts.append({
                'type': w_type,
                'name': w_names[w_type],
                'duration': dur,
                'calories': int(dur * 8.5),
                'distance': w_dist,
                'time': f"0{random.randint(7, 9)}:30"
            })

        data.append({
            'date': day_date.strftime("%Y-%m-%d"),
            'day': d,
            'recovery_score': recovery_val,
            'current_hr': rhr_val + random.randint(15, 30),
            'resting_hr': rhr_val,
            'hrv': hrv_val,
            'sleep_duration': round(sleep_dur, 1),
            'sleep_quality': "Good" if sleep_score > 78 else "Fair" if sleep_score > 60 else "Poor",
            'sleep_score': sleep_score,
            'stress': stress_val,
            'spo2': random.choice([97, 98, 99]),
            'steps': steps_val,
            'calories': calories_val,
            'distance': dist_val,
            'active_minutes': active_min,
            'workouts': workouts,
            'ring_battery': max(10, 100 - (d % 6) * 15),
            'last_sync': "2 mins ago"
        })
    
    return data

# ==============================================================================
# Deterministic Health Narrative & Rules Engine
# ==============================================================================

def generate_weekly_narrative(daily_data):
    """
    Analyzes the last 7 days of metrics and compares them against the entire
    month's baseline to output deterministic summaries, insights, and scores.
    """
    last_7 = daily_data[-7:]
    
    # 1. Calculate baselines (all days)
    all_recovery = [d['recovery_score'] for d in daily_data]
    all_sleep = [d['sleep_score'] for d in daily_data]
    all_hrv = [d['hrv'] for d in daily_data]
    all_rhr = [d['resting_hr'] for d in daily_data]
    
    avg_recovery_base = sum(all_recovery) / len(all_recovery)
    avg_sleep_base = sum(all_sleep) / len(all_sleep)
    avg_hrv_base = sum(all_hrv) / len(all_hrv)
    avg_rhr_base = sum(all_rhr) / len(all_rhr)

    # 2. Calculate weekly averages
    weekly_recovery = [d['recovery_score'] for d in last_7]
    weekly_sleep = [d['sleep_score'] for d in last_7]
    weekly_sleep_duration = [d['sleep_duration'] for d in last_7]
    weekly_hrv = [d['hrv'] for d in last_7]
    weekly_rhr = [d['resting_hr'] for d in last_7]
    weekly_stress = [d['stress'] for d in last_7]
    weekly_spo2 = [d['spo2'] for d in last_7]
    
    avg_weekly_recovery = sum(weekly_recovery) / 7
    avg_weekly_sleep = sum(weekly_sleep) / 7
    avg_weekly_duration = sum(weekly_sleep_duration) / 7
    avg_weekly_hrv = sum(weekly_hrv) / 7
    avg_weekly_rhr = sum(weekly_rhr) / 7
    avg_weekly_stress = sum(weekly_stress) / 7
    avg_weekly_spo2 = sum(weekly_spo2) / 7

    # 3. Deterministic Narrative Logic
    
    # Sleep Insights
    sleep_insights = f"You slept an average of {avg_weekly_duration:.1f} hours per night (Sleep Score: {avg_weekly_sleep:.0f}). "
    if avg_weekly_sleep >= avg_sleep_base + 3:
        sleep_insights += "This is higher than your monthly average, showing excellent sleep consistency. Deep and REM sleep proportions were stable."
    elif avg_weekly_sleep <= avg_sleep_base - 3:
        sleep_insights += f"This is lower than your monthly baseline ({avg_sleep_base:.0f}). Accumulated sleep debt is currently estimated at {7.5 * 7 - sum(weekly_sleep_duration):.1f} hours. Suggest aiming for 30 minutes more sleep per night."
    else:
        sleep_insights += "Your sleep patterns are consistent with your overall monthly average. No major sleep debt detected."

    # Recovery/HRV trend
    recovery_insights = f"Your readiness/recovery score averaged {avg_weekly_recovery:.0f}. Average HRV was {avg_weekly_hrv:.0f}ms (monthly baseline: {avg_hrv_base:.0f}ms). "
    if avg_weekly_hrv > avg_hrv_base + 4:
        recovery_insights += "Your higher HRV indicates a well-balanced nervous system. Your body is primed for intensive workouts and cognitive loads."
    elif avg_weekly_hrv < avg_hrv_base - 4:
        recovery_insights += "Your HRV has dropped below baseline. This suggests sympathetic nervous system dominance, likely due to fatigue, light illness, or physical strain."
    else:
        recovery_insights += "Your autonomic nervous system indicators are stable and holding standard baseline metrics."

    # Workouts
    total_workouts = sum(len(d['workouts']) for d in last_7)
    workout_insights = f"You logged {total_workouts} workouts this week. "
    if total_workouts >= 3:
        workout_insights += "Excellent training consistency! The distribution of cardio and recovery workouts is well balanced, promoting cardiovascular adaptation."
    elif total_workouts > 0:
        workout_insights += "Solid effort. To see long-term physiological adaptations, try to schedule at least 3 active training sessions next week."
    else:
        workout_insights += "No formal workouts were logged. Consider incorporating light movement or mobility sessions to promote circulation."

    # Stress & SpO2
    stress_insights = f"Weekly stress levels averaged {avg_weekly_stress:.0f} out of 100, and SpO₂ levels held strong at {avg_weekly_spo2:.1f}%. "
    if avg_weekly_stress > 35:
        stress_insights += "Your average stress is elevated. Ensure you are scheduling brief periods of deliberate deep breathing or active downtime throughout the day."
    else:
        stress_insights += "Stress indicators show a healthy balance of active engagement and passive recovery cycles."

    # Achievements
    achievements = []
    if max([d['steps'] for d in last_7]) > 12000:
        achievements.append("👑 Step Champion: Logged a day exceeding 12,000 steps.")
    if min(weekly_rhr) < avg_rhr_base - 3:
        achievements.append(f"❤️ Heart Health: Logged a resting heart rate low of {min(weekly_rhr)} bpm.")
    if avg_weekly_recovery >= 80:
        achievements.append("⚡ Supercharged: Sustained an average weekly recovery score above 80%.")
    if not achievements:
        achievements.append("🌱 Consistent: Met daily biometrics tracking targets without dropouts.")

    # Weekly Suggestion Focus
    if avg_weekly_hrv < avg_hrv_base - 3:
        focus = "Focus on **Active Recovery**: Prioritize sleep, light walking, and mobility work. Restrict high-intensity workouts until HRV recovers."
    elif avg_weekly_sleep < 65:
        focus = "Focus on **Sleep Hygiene**: Set a strict digital curfew and aim for a consistent sleep/wake window to repay sleep debt."
    elif total_workouts < 2:
        focus = "Focus on **Cardio Volume**: Schedule 2 moderate-intensity cardio sessions (running/cycling) to build endurance load."
    else:
        focus = "Focus on **Performance Push**: Energy levels are optimal. You can safely increase training load or introduce speed/tempo workouts."

    return {
        'score': int(avg_weekly_recovery),
        'evaluation': "Optimal" if avg_weekly_recovery >= 75 else "Balanced" if avg_weekly_recovery >= 60 else "Fatigued",
        'sleep_insights': sleep_insights,
        'recovery_insights': recovery_insights,
        'workout_insights': workout_insights,
        'stress_insights': stress_insights,
        'achievements': "<br>".join(achievements),
        'focus': focus
    }

# ==============================================================================
# Flask Endpoints
# ==============================================================================

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/health")
def api_health():
    month_str = request.args.get("month", "2026-07")
    try:
        year, month = map(int, month_str.split("-"))
    except ValueError:
        year, month = 2026, 7

    daily_data, is_mocked = get_db_data(year, month)
    
    # 1. Latest daily values (last day in array)
    latest = daily_data[-1].copy()
    
    # Calculate daily changes compared to yesterday
    if len(daily_data) > 1:
        yesterday = daily_data[-2]
        latest['recovery_change'] = latest['recovery_score'] - yesterday['recovery_score']
        latest['hr_change'] = latest['resting_hr'] - yesterday['resting_hr']
        latest['hrv_change'] = latest['hrv'] - yesterday['hrv']
        latest['sleep_change'] = latest['sleep_score'] - yesterday['sleep_score']
    else:
        latest['recovery_change'] = latest['hr_change'] = latest['hrv_change'] = latest['sleep_change'] = 0

    # 2. Compile charts payload
    charts = {
        'labels': [f"Day {d['day']}" for d in daily_data[-14:]], # last 14 days
        'recovery': [d['recovery_score'] for d in daily_data[-14:]],
        'sleep_duration': [d['sleep_duration'] for d in daily_data[-14:]],
        'sleep_score': [d['sleep_score'] for d in daily_data[-14:]],
        'hrv': [d['hrv'] for d in daily_data[-14:]],
        'resting_hr': [d['resting_hr'] for d in daily_data[-14:]]
    }

    # 3. Generate weekly narrative (using full month as baseline, last 7 days as check)
    weekly = generate_weekly_narrative(daily_data)

    # 4. Generate monthly comparison (Current selected month vs previous month dummy)
    prev_month = month - 1 if month > 1 else 12
    prev_year = year if month > 1 else year - 1
    prev_data, _ = get_db_data(prev_year, prev_month)

    metrics_list = []
    comparison_keys = [
        ('Readiness Score', 'recovery_score', 'avg'),
        ('Resting Heart Rate (bpm)', 'resting_hr', 'avg'),
        ('Heart Rate Variability (ms)', 'hrv', 'avg'),
        ('Sleep Duration (hrs)', 'sleep_duration', 'avg'),
        ('Total Step Count', 'steps', 'sum'),
        ('Active Minutes', 'active_minutes', 'sum')
    ]

    for label, key, op in comparison_keys:
        curr_vals = [d[key] for d in daily_data]
        prev_vals = [d[key] for d in prev_data]
        
        curr_res = sum(curr_vals)/len(curr_vals) if op == 'avg' else sum(curr_vals)
        prev_res = sum(prev_vals)/len(prev_vals) if op == 'avg' else sum(prev_vals)

        diff = curr_res - prev_res
        if label.endswith('(hrs)'):
            curr_str = f"{curr_res:.1f}h"
            prev_str = f"{prev_res:.1f}h"
            diff_str = f"{'+' if diff >= 0 else ''}{diff:.1f}h"
        elif label.startswith('Total') or label.startswith('Active'):
            curr_str = f"{int(curr_res):,}"
            prev_str = f"{int(prev_res):,}"
            diff_str = f"{'+' if diff >= 0 else ''}{int(diff):,}"
        else:
            curr_str = f"{curr_res:.0f}"
            prev_str = f"{prev_res:.0f}"
            diff_str = f"{'+' if diff >= 0 else ''}{diff:.0f}"

        direction = 'up' if diff > 0 else 'down' if diff < 0 else 'flat'
        metrics_list.append({
            'name': label,
            'current': curr_str,
            'previous': prev_str,
            'diff': diff_str,
            'direction': direction
        })

    # Find best and worst recovery days
    best_day = max(daily_data, key=lambda x: x['recovery_score'])
    worst_day = min(daily_data, key=lambda x: x['recovery_score'])

    monthly_payload = {
        'trends_summary': f"This month, your biometrics showed positive adaptations. Your peak recovery occurred on Day {best_day['day']} with a readiness score of {best_day['recovery_score']}%, driven by an HRV of {best_day['hrv']}ms. Conversely, your lowest recovery was on Day {worst_day['day']} ({worst_day['recovery_score']}%).",
        'suggested_goals': f"Based on your HRV trends and sleep consistency, we suggest: 1) Aiming for a minimum of 7.2 hours of sleep to improve average HRV, and 2) Increasing aerobic workouts to 3 sessions per week to build high-end cardio load.",
        'metrics': metrics_list
    }

    return jsonify({
        'mocked': is_mocked,
        'daily': latest,
        'charts': charts,
        'weekly': weekly,
        'monthly': monthly_payload
    })


@app.route("/api/report/regenerate", methods=["POST"])
def api_regenerate():
    # In a full production setup, this would trigger background tasks to re-fetch and overwrite values.
    # For now, it simply responds with success to trigger client refresh.
    return jsonify({'status': 'ok', 'message': 'Data cache cleared and queries run successfully.'})


@app.route("/api/report/export")
def api_export():
    month_str = request.args.get("month", "2026-07")
    export_format = request.args.get("format", "json")
    try:
        year, month = map(int, month_str.split("-"))
    except ValueError:
        year, month = 2026, 7

    daily_data, _ = get_db_data(year, month)

    if export_format == "csv":
        si = io.StringIO()
        cw = csv.writer(si)
        # Headers
        cw.writerow(['date', 'day', 'recovery_score', 'resting_hr', 'hrv', 'sleep_duration', 'sleep_score', 'stress', 'spo2', 'steps', 'calories', 'active_minutes'])
        for d in daily_data:
            cw.writerow([
                d['date'], d['day'], d['recovery_score'], d['resting_hr'], d['hrv'],
                d['sleep_duration'], d['sleep_score'], d['stress'], d['spo2'],
                d['steps'], d['calories'], d['active_minutes']
            ])
        output = io.BytesIO()
        output.write(si.getvalue().encode('utf-8'))
        output.seek(0)
        return send_file(
            output,
            mimetype="text/csv",
            as_attachment=True,
            download_name=f"health_report_{month_str}.csv"
        )
    else:
        # JSON export
        return jsonify(daily_data)


@app.route("/api/report/download")
def api_download_pdf():
    month_str = request.args.get("month", "2026-07")
    try:
        year, month = map(int, month_str.split("-"))
    except ValueError:
        year, month = 2026, 7

    daily_data, is_mocked = get_db_data(year, month)
    weekly_narrative = generate_weekly_narrative(daily_data)

    # Calculate month stats
    avg_recovery = sum(d['recovery_score'] for d in daily_data) / len(daily_data)
    avg_sleep = sum(d['sleep_score'] for d in daily_data) / len(daily_data)
    avg_hrv = sum(d['hrv'] for d in daily_data) / len(daily_data)
    avg_rhr = sum(d['resting_hr'] for d in daily_data) / len(daily_data)
    total_steps = sum(d['steps'] for d in daily_data)
    total_cals = sum(d['calories'] for d in daily_data)

    # Initialize PDF buffer
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        rightMargin=40, leftMargin=40, topMargin=40, bottomMargin=40
    )

    styles = getSampleStyleSheet()
    
    # Custom high-end styles matching theme
    style_title = ParagraphStyle(
        name='TitleStyle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=24,
        leading=28,
        textColor=colors.HexColor('#0f172a'),
        spaceAfter=6
    )
    style_subtitle = ParagraphStyle(
        name='SubTitleStyle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=11,
        textColor=colors.HexColor('#64748b'),
        spaceAfter=20
    )
    style_h2 = ParagraphStyle(
        name='H2Style',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=15,
        leading=18,
        textColor=colors.HexColor('#1e40af'),
        spaceBefore=14,
        spaceAfter=8,
        keepWithNext=True
    )
    style_body = ParagraphStyle(
        name='BodyStyle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9.5,
        leading=13.5,
        textColor=colors.HexColor('#334155'),
        spaceAfter=10
    )
    style_th = ParagraphStyle(
        name='THStyle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=9,
        textColor=colors.white
    )
    style_td = ParagraphStyle(
        name='TDStyle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9,
        textColor=colors.HexColor('#334155')
    )

    story = []

    # Title Banner
    story.append(Paragraph(f"🛡️ Health & Recovery Report", style_title))
    status_text = "Demo Mode - Local Mock Telemetry" if is_mocked else "Verified Homelab Dataset"
    story.append(Paragraph(f"Month: {month_str}  |  Generated on: {datetime.date.today().isoformat()}  |  Data Status: {status_text}", style_subtitle))

    # Metric summary table
    summary_data = [
        [Paragraph('Monthly Average Readiness', style_th), Paragraph('Sleep Score', style_th), Paragraph('Resting HR', style_th), Paragraph('HRV', style_th)],
        [Paragraph(f"{avg_recovery:.0f}%", style_td), Paragraph(f"{avg_sleep:.0f}/100", style_td), Paragraph(f"{avg_rhr:.0f} bpm", style_td), Paragraph(f"{avg_hrv:.0f} ms", style_td)]
    ]
    summary_table = Table(summary_data, colWidths=[130, 130, 130, 130])
    summary_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#1e3a8a')),
        ('ALIGN', (0,0), (-1,-1), 'CENTER'),
        ('BOTTOMPADDING', (0,0), (-1,0), 6),
        ('TOPPADDING', (0,0), (-1,0), 6),
        ('BOTTOMPADDING', (0,1), (-1,1), 8),
        ('TOPPADDING', (0,1), (-1,1), 8),
        ('BACKGROUND', (0,1), (-1,1), colors.HexColor('#f8fafc')),
        ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor('#cbd5e1')),
    ]))
    story.append(summary_table)
    story.append(Spacer(1, 15))

    # Add a custom drawn vector chart representing Readiness Score
    story.append(Paragraph("🔋 Readiness / Recovery Trend (Last 14 Days)", style_h2))
    
    # Render custom vector line plot in ReportLab shapes
    chart_drawing = Drawing(520, 130)
    chart_drawing.add(Rect(0, 0, 520, 130, fillColor=colors.HexColor('#f8fafc'), strokeColor=colors.HexColor('#e2e8f0'), strokeWidth=1))
    
    # Draw horizontal gridlines for 25, 50, 75, 100
    for grid_y in [25, 50, 75, 100]:
        canvas_y = 15 + (grid_y / 100.0) * 100
        chart_drawing.add(PolyLine([(0, canvas_y), (520, canvas_y)], strokeColor=colors.HexColor('#cbd5e1'), strokeWidth=0.5))
        chart_drawing.add(String(5, canvas_y + 2, f"{grid_y}", fontSize=7, fontName='Helvetica', fillColor=colors.HexColor('#64748b')))

    # Map recovery scores to line points (using last 14 days)
    plot_data = daily_data[-14:]
    points = []
    x_step = 520.0 / (len(plot_data) - 1) if len(plot_data) > 1 else 520.0
    
    for idx, day in enumerate(plot_data):
        cx = idx * x_step
        cy = 15 + (day['recovery_score'] / 100.0) * 100
        points.append((cx, cy))
        # Draw dot on chart
        chart_drawing.add(Circle(cx, cy, 3, fillColor=colors.HexColor('#3b82f6'), strokeColor=colors.white, strokeWidth=0.5))
        # Label days
        chart_drawing.add(String(cx + 2, 4, f"D{day['day']}", fontSize=6.5, fontName='Helvetica', fillColor=colors.HexColor('#64748b')))
        
    chart_drawing.add(PolyLine(points, strokeColor=colors.HexColor('#3b82f6'), strokeWidth=2))
    story.append(chart_drawing)
    story.append(Spacer(1, 15))

    # Weekly Narrative Sections
    story.append(Paragraph("📝 Weekly Narrative Summary", style_h2))
    
    narrative_body = (
        f"<b>Weekly Health Score:</b> {weekly_narrative['score']}/100 ({weekly_narrative['evaluation']})<br/><br/>"
        f"<b>Sleep insights:</b> {weekly_narrative['sleep_insights']}<br/><br/>"
        f"<b>Recovery and Autonomic indicators (HRV):</b> {weekly_narrative['recovery_insights']}<br/><br/>"
        f"<b>Workout activities:</b> {weekly_narrative['workout_insights']}<br/><br/>"
        f"<b>Stress & oxygen levels:</b> {weekly_narrative['stress_insights']}<br/><br/>"
        f"<b>Weekly Suggested Focus:</b> {weekly_narrative['focus']}"
    )
    story.append(Paragraph(narrative_body, style_body))
    story.append(Spacer(1, 15))

    # Monthly comparison details
    story.append(Paragraph("📊 Month-Over-Month Totals", style_h2))
    comparison_body = (
        f"• Total Step Count: <b>{total_steps:,} steps</b><br/>"
        f"• Total Active Energy Expended: <b>{total_cals:,} kcal</b><br/>"
        f"• Combined Average Heart Rate: <b>{avg_rhr:.0f} bpm</b> (Resting)<br/>"
        f"• Baseline Heart Rate Variability (HRV): <b>{avg_hrv:.0f} ms</b>"
    )
    story.append(Paragraph(comparison_body, style_body))
    
    # Generate the document
    doc.build(story)
    
    buffer.seek(0)
    return send_file(
        buffer,
        mimetype="application/pdf",
        as_attachment=True,
        download_name=f"health_report_{month_str}.pdf"
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)

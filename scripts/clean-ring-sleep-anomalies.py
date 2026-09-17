#!/usr/bin/env python3
"""Safely remove >12-hour Ring sleep samples from VictoriaMetrics.

VictoriaMetrics' delete_series API deletes complete time series, not individual
samples. This utility therefore exports the sleep series, removes bad samples
locally, deletes the affected series, and imports the retained samples.

It is a dry run by default. Use --apply --yes only after checking its report.
Run it against a localhost kubectl port-forward rather than the public service.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import re
import sys
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

METRICS = (
    "biometric_sleep_total_min",
    "biometric_sleep_deep_min",
    "biometric_sleep_rem_min",
    "biometric_sleep_light_min",
)
MAX_SLEEP_MINUTES = 12 * 60
MATCH_TOLERANCE_MS = 5 * 60 * 1000
UTC = dt.timezone.utc


def http_request(url: str, method: str = "GET", fields: list[tuple[str, str]] | None = None) -> bytes:
    body = urlencode(fields or []).encode() if fields else None
    request = Request(url, data=body, method=method)
    with urlopen(request, timeout=30) as response:
        return response.read()


def export_series(
    base_url: str,
    device: str,
    start: dt.datetime | None,
    end: dt.datetime | None,
) -> list[dict[str, Any]]:
    metric_pattern = "|".join(METRICS)
    selector = f'{{device="{device}",__name__=~"^({metric_pattern})$"}}'
    # Explicitly use the epoch and `now` when no bounds are supplied. This
    # avoids VictoriaMetrics' endpoint default window and scans all data still
    # retained by its configured retention period.
    params: list[tuple[str, str]] = [("match[]", selector)]
    if start is None and end is None:
        params.extend([("start", "0"), ("end", "now")])
    else:
        if start is not None:
            params.append(("start", start.isoformat().replace("+00:00", "Z")))
        if end is not None:
            params.append(("end", end.isoformat().replace("+00:00", "Z")))
    query = urlencode(params)
    request = Request(f"{base_url}/api/v1/export?{query}")
    result = []
    with urlopen(request, timeout=60) as response:
        for raw_line in response:
            if not raw_line.strip():
                continue
            result.append(json.loads(raw_line))
    return result


def number(value: Any) -> float | None:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) else None


def timestamp_ms(value: Any) -> int | None:
    parsed = number(value)
    if parsed is None:
        return None
    return int(parsed if parsed >= 100_000_000_000 else parsed * 1000)


def clean_exported_series(series: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    abnormal_timestamps: list[int] = []
    abnormal: list[dict[str, Any]] = []
    for item in series:
        if item.get("metric", {}).get("__name__") != "biometric_sleep_total_min":
            continue
        for raw_timestamp, raw_value in zip(item.get("timestamps", []), item.get("values", [])):
            timestamp = timestamp_ms(raw_timestamp)
            value = number(raw_value)
            if timestamp is not None and value is not None and value > MAX_SLEEP_MINUTES:
                abnormal_timestamps.append(timestamp)
                abnormal.append(
                    {
                        "timestamp_ms": timestamp,
                        "date": dt.datetime.fromtimestamp(timestamp / 1000, tz=UTC).date().isoformat(),
                        "minutes": value,
                    }
                )

    cleaned: list[dict[str, Any]] = []
    for item in series:
        metric_name = item.get("metric", {}).get("__name__")
        kept_timestamps: list[int] = []
        kept_values: list[float] = []
        for raw_timestamp, raw_value in zip(item.get("timestamps", []), item.get("values", [])):
            timestamp = timestamp_ms(raw_timestamp)
            value = number(raw_value)
            if timestamp is None or value is None:
                continue
            is_bad_total = metric_name == "biometric_sleep_total_min" and value > MAX_SLEEP_MINUTES
            belongs_to_bad_session = metric_name != "biometric_sleep_total_min" and any(
                abs(timestamp - bad_timestamp) <= MATCH_TOLERANCE_MS
                for bad_timestamp in abnormal_timestamps
            )
            if not is_bad_total and not belongs_to_bad_session:
                kept_timestamps.append(timestamp)
                kept_values.append(value)
        cleaned.append({"metric": item.get("metric", {}), "timestamps": kept_timestamps, "values": kept_values})
    return cleaned, abnormal


def escape_label(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def prometheus_import_payload(series: list[dict[str, Any]]) -> bytes:
    lines: list[str] = []
    for item in series:
        metric = item.get("metric", {})
        name = metric.get("__name__")
        if not name:
            continue
        labels = ",".join(
            f'{key}="{escape_label(str(value))}"'
            for key, value in sorted(metric.items())
            if key != "__name__"
        )
        metric_text = f"{name}{{{labels}}}" if labels else name
        for timestamp, value in zip(item["timestamps"], item["values"]):
            lines.append(f"{metric_text} {value:.17g} {timestamp}\n")
    return "".join(lines).encode()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--url",
        default="http://192.168.178.214:8428",
        help="VictoriaMetrics URL (default: Ring Health LAN service)",
    )
    parser.add_argument("--device", default="colmi_r02")
    parser.add_argument(
        "--start",
        help="Optional ISO-8601 start; omit to scan all retained history",
    )
    parser.add_argument(
        "--end",
        help="Optional ISO-8601 end; omit to scan all retained history",
    )
    parser.add_argument("--backup", help="Path for the pre-cleanup JSONL export")
    parser.add_argument("--apply", action="store_true", help="Delete and re-import data")
    parser.add_argument("--yes", action="store_true", help="Confirm destructive operation")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.:-]+", args.device):
        print("Refusing unsupported device label", file=sys.stderr)
        return 2
    if args.apply and not args.yes:
        print("Refusing to modify VictoriaMetrics: --apply requires --yes", file=sys.stderr)
        return 2
    try:
        start = (
            dt.datetime.fromisoformat(args.start.replace("Z", "+00:00")).astimezone(UTC)
            if args.start
            else None
        )
        end = (
            dt.datetime.fromisoformat(args.end.replace("Z", "+00:00")).astimezone(UTC)
            if args.end
            else None
        )
        exported = export_series(args.url.rstrip("/"), args.device, start, end)
        cleaned, abnormal = clean_exported_series(exported)
        if args.apply:
            backup_path = args.backup or f"ring-sleep-export-{dt.datetime.now(tz=UTC):%Y%m%dT%H%M%SZ}.jsonl"
            with open(backup_path, "w", encoding="utf-8") as backup_file:
                for item in exported:
                    backup_file.write(json.dumps(item) + "\n")
            print(f"Saved pre-cleanup export to {backup_path}")
    except Exception as exc:
        print(f"VictoriaMetrics export failed: {exc}", file=sys.stderr)
        return 1

    scope = "all retained history" if not args.start and not args.end else f"{args.start or 'beginning'} to {args.end or 'now'}"
    print(f"Exported {len(exported)} sleep series for device={args.device} ({scope})")
    print(f"Found {len(abnormal)} abnormal sample(s) over {MAX_SLEEP_MINUTES // 60} hours")
    for item in abnormal:
        print(f"  {item['date']}: {item['minutes']:.1f} minutes")
    if not abnormal:
        print("Nothing to clean.")
        return 0
    if not args.apply:
        print("Dry run only. Re-run with --apply --yes to replace these series.")
        return 0

    base_url = args.url.rstrip("/")
    metric_pattern = "|".join(METRICS)
    selector = f'{{device="{args.device}",__name__=~"^({metric_pattern})$"}}'
    try:
        http_request(
            f"{base_url}/api/v1/admin/tsdb/delete_series",
            method="POST",
            fields=[("match[]", selector)],
        )
        payload = prometheus_import_payload(cleaned)
        if payload:
            request = Request(
                f"{base_url}/api/v1/import/prometheus",
                data=payload,
                method="POST",
                headers={"Content-Type": "text/plain"},
            )
            with urlopen(request, timeout=60) as response:
                response.read()
        print("VictoriaMetrics sleep series replaced with cleaned samples.")
        print("Verify with /api/v1/query and refresh the dashboard.")
        return 0
    except Exception as exc:
        print(
            "Cleanup failed after deletion. Retained samples can be re-imported from the export backup if needed: "
            f"{exc}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

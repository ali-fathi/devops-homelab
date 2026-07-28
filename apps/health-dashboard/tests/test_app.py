import datetime as dt
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from werkzeug.security import generate_password_hash

TEST_USERNAME = "dashboard-test-user"
TEST_PASSWORD = "correct-horse-battery-staple"
os.environ.setdefault("DASHBOARD_USERNAME", TEST_USERNAME)
os.environ.setdefault(
    "DASHBOARD_PASSWORD_HASH",
    generate_password_hash(TEST_PASSWORD, method="pbkdf2:sha256:1000000"),
)
os.environ.setdefault("FLASK_SECRET_KEY", "test-only-secret-key-with-at-least-32-bytes")

sys.path.insert(0, str(Path(__file__).parents[1]))
import app as health_app


class HealthDashboardTests(unittest.TestCase):
    def setUp(self):
        self.client = health_app.app.test_client()
        self.original_mock_mode = health_app.MOCK_DATA_ENV
        self.login(self.client)

    def tearDown(self):
        health_app.MOCK_DATA_ENV = self.original_mock_mode

    def login(self, client, username=TEST_USERNAME, password=TEST_PASSWORD):
        client.get("/login")
        with client.session_transaction() as session_data:
            csrf_token = session_data["csrf_token"]
        return client.post(
            "/login",
            data={
                "username": username,
                "password": password,
                "csrf_token": csrf_token,
            },
        )

    def test_login_is_required_for_dashboard_and_api(self):
        anonymous_client = health_app.app.test_client()
        dashboard_response = anonymous_client.get("/")
        api_response = anonymous_client.get("/api/health")

        self.assertEqual(dashboard_response.status_code, 302)
        self.assertEqual(dashboard_response.headers["Location"], "/login")
        self.assertEqual(api_response.status_code, 401)
        self.assertEqual(api_response.get_json()["status"], "unauthorized")

    def test_valid_login_creates_authenticated_session(self):
        client = health_app.app.test_client()
        response = self.login(client)

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.headers["Location"], "/")
        with client.session_transaction() as session_data:
            self.assertTrue(session_data["authenticated"])
            self.assertEqual(session_data["username"], TEST_USERNAME)

        dashboard_response = client.get("/")
        self.assertEqual(dashboard_response.status_code, 200)
        self.assertIn(b"Sign out", dashboard_response.data)

    def test_invalid_login_is_rejected(self):
        client = health_app.app.test_client()
        response = self.login(client, password="wrong-password")

        self.assertEqual(response.status_code, 401)
        with client.session_transaction() as session_data:
            self.assertNotIn("authenticated", session_data)

    def test_missing_authentication_configuration_fails_closed(self):
        client = health_app.app.test_client()
        with patch.object(health_app, "AUTH_CONFIGURED", False):
            login_response = client.get("/login")
            api_response = client.get("/api/health")

        self.assertEqual(login_response.status_code, 503)
        self.assertEqual(api_response.status_code, 503)
        self.assertEqual(
            api_response.get_json()["status"], "authentication_unavailable"
        )

    def test_process_health_endpoint(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"status": "healthy"})

    def test_mock_data_is_explicit_and_stops_at_today(self):
        health_app.MOCK_DATA_ENV = True
        response = self.client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertTrue(payload["mocked"])
        self.assertLessEqual(
            dt.date.fromisoformat(payload["daily"]["date"]), dt.date.today()
        )

    def test_production_failure_does_not_return_mock_data(self):
        health_app.MOCK_DATA_ENV = False
        with patch.object(
            health_app.InfluxDBClient,
            "ping",
            side_effect=OSError("InfluxDB unavailable"),
        ):
            response = self.client.get("/api/health")
        self.assertEqual(response.status_code, 503)
        payload = response.get_json()
        self.assertFalse(payload["mocked"])
        self.assertEqual(payload["status"], "data_unavailable")
        self.assertEqual(payload["source"], "influxdb")

    def test_ring_endpoint_returns_only_stored_victoriametrics_metrics(self):
        health_app.MOCK_DATA_ENV = False
        now_ms = int(dt.datetime.now(tz=dt.timezone.utc).timestamp() * 1000)
        series = {name: [] for name in health_app.RING_METRICS}
        series.update(
            {
                "biometric_hr_bpm": [(now_ms - 300_000, 61.0), (now_ms, 72.0)],
                "biometric_steps": [(now_ms, 840.0)],
                "biometric_sleep_total_min": [(now_ms, 450.0)],
                # Importers can write stages a few milliseconds apart from
                # the total session sample; the summary must still join them.
                "biometric_sleep_deep_min": [(now_ms + 1_000, 90.0)],
                "biometric_sleep_rem_min": [(now_ms - 1_000, 110.0)],
                "biometric_sleep_light_min": [(now_ms + 2_000, 250.0)],
                "ring_battery_pct": [(now_ms, 77.0)],
                "ring_charging": [(now_ms, 0.0)],
            }
        )

        with patch.object(health_app, "vm_export_ring_metrics", return_value=series):
            response = self.client.get("/api/ring?range=24h")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertFalse(payload["mocked"])
        self.assertEqual(payload["device"], "colmi_r02")
        self.assertEqual(payload["summary"]["latest_hr"], 72)
        self.assertEqual(payload["summary"]["resting_hr_24h"], 61)
        self.assertEqual(payload["summary"]["period_steps"], 840)
        self.assertEqual(payload["summary"]["sleep_total_min"], 450)
        self.assertEqual(payload["summary"]["sleep_deep_min"], 90)
        self.assertEqual(payload["summary"]["sleep_rem_min"], 110)
        self.assertEqual(payload["summary"]["sleep_light_min"], 250)
        self.assertEqual(payload["summary"]["battery"], 77)
        self.assertFalse(payload["summary"]["charging"])

    def test_ring_endpoint_rejects_unsupported_ranges(self):
        response = self.client.get("/api/ring?range=1y")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["status"], "invalid_request")

    def test_victoriametrics_export_parser_keeps_original_timestamps(self):
        class ExportResponse:
            def raise_for_status(self):
                return None

            def iter_lines(self, decode_unicode=False):
                return [
                    b'{"metric":{"__name__":"biometric_hr_bpm","device":"colmi_r02"},'
                    b'"values":[65,71],"timestamps":[1700000000000,1700000300]}'
                ]

        start = dt.datetime(2023, 11, 14, tzinfo=dt.timezone.utc)
        end = start + dt.timedelta(days=1)
        with patch.object(health_app.requests, "get", return_value=ExportResponse()):
            series = health_app.vm_export_ring_metrics(start, end)

        self.assertEqual(
            series["biometric_hr_bpm"],
            [(1700000000000, 65.0), (1700000300000, 71.0)],
        )

    def test_real_merge_keeps_missing_values_empty(self):
        class EmptyQueryResult:
            def get_points(self):
                return []

        class EmptyInfluxClient:
            def __init__(self):
                self.queries = []

            def query(self, query):
                self.queries.append(query)
                return EmptyQueryResult()

        influx_client = EmptyInfluxClient()
        with patch.object(health_app, "vm_query_range", return_value={}):
            rows = health_app.fetch_and_merge_production_data(
                influx_client, dt.date.today().year, dt.date.today().month
            )

        self.assertTrue(any('"duration"' in query for query in influx_client.queries))
        self.assertTrue(any('"type"' in query for query in influx_client.queries))

        self.assertLessEqual(dt.date.fromisoformat(rows[-1]["date"]), dt.date.today())
        self.assertTrue(all(row["data_status"] == "no-data" for row in rows))
        self.assertTrue(all(row["recovery_score"] is None for row in rows))


if __name__ == "__main__":
    unittest.main()

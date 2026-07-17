import datetime as dt
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import app as health_app


class HealthDashboardTests(unittest.TestCase):
    def setUp(self):
        self.client = health_app.app.test_client()
        self.original_mock_mode = health_app.MOCK_DATA_ENV

    def tearDown(self):
        health_app.MOCK_DATA_ENV = self.original_mock_mode

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

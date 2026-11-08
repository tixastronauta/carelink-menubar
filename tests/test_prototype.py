import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from datetime import datetime, timezone
from carelink_proto.model import normalize
from carelink_proto.chart import render
from carelink_proto.security import Transport, DISPLAY, TOKEN, USER, ROOT, save_private, validate_private
from carelink_proto.login import callback_code
from carelink_proto.client import fetch

NOW = datetime(2026, 10, 28, 12, tzinfo=timezone.utc)


def payload():
    return {"patientData": {"bgUnits": "MGDL", "lastSG": {"sg": 112, "datetime": "2026-10-28T12:00:00Z"},
        "lastSGTrend": "UP", "activeInsulin": {"amount": 0},
        "sgs": [{"sg": 100, "datetime": "2026-10-28T11:55:00Z"}]}}


class ModelTests(unittest.TestCase):
    def test_current_values_and_zero_insulin(self):
        data = normalize(payload(), NOW)
        self.assertEqual((data["glucose"], data["unit"], data["trend"], data["active_insulin_units"]), (112, "mg/dL", "UP", 0))
        self.assertFalse(data["stale"])
        self.assertEqual(data["flex_compatibility"], "unverified")

    def test_missing_values_are_not_zero(self):
        data = normalize({"activeInsulin": {}}, NOW)
        self.assertIsNone(data["glucose"])
        self.assertIsNone(data["active_insulin_units"])
        self.assertIsNone(data["unit"])
        self.assertTrue(data["stale"])

    def test_unknown_schema_fails(self):
        for raw in ({"error": "unauthorized"}, {"patientData": None}, []):
            with self.assertRaises(ValueError): normalize(raw, NOW)

    def test_stale_naive_future_and_invalid_glucose(self):
        for stamp in ("2026-10-27T12:00:00Z", "2026-10-28T12:00:00", "2026-10-29T12:00:00Z", "bad"):
            raw = payload()
            raw["patientData"]["lastSG"] = {"sg": -1, "datetime": stamp}
            data = normalize(raw, NOW)
            self.assertTrue(data["stale"])
            self.assertIsNone(data["glucose"])

    def test_history_sorted_deduplicated_and_invalid_filtered(self):
        raw = payload()
        raw["patientData"]["sgs"] *= 2
        raw["patientData"]["sgs"] += [{"sg": float("nan"), "datetime": "2026-10-28T11:56:00Z"}, {"sg": 0}, {"sg": 101, "datetime": "2026-10-28T11:50:00Z"}]
        data = normalize(raw, NOW)
        self.assertEqual([p["glucose"] for p in data["history"]], [101, 100])
        self.assertTrue(any("invalid" in w for w in data["warnings"]))

    def test_unit_is_not_assumed(self):
        raw = payload()
        raw["patientData"]["bgUnits"] = "unknown"
        data = normalize(raw, NOW)
        self.assertIsNone(data["unit"])
        self.assertIn("Chart unavailable", render(data))

    def test_chart_is_offline_and_escapes_content(self):
        data = normalize(payload(), NOW)
        data["warnings"] = ["<script>alert(1)</script>"]
        page = render(data, True)
        self.assertIn("DEMO — SYNTHETIC DATA", page)
        self.assertNotIn("<script>", page)
        self.assertNotIn("https://", page)
        self.assertIn("circle", page)


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.transport = Transport()
        self.transport.session.request = Mock(return_value=Mock(status_code=200))

    def test_only_read_post_body_is_allowed(self):
        self.transport.post(DISPLAY, data=json.dumps({"username": "synthetic", "role": "patient"}))
        self.transport.session.request.assert_called_once()
        kwargs = self.transport.session.request.call_args.kwargs
        self.assertFalse(kwargs["allow_redirects"])
        self.assertEqual(kwargs["timeout"], (10, 30))

    def test_writes_and_other_hosts_blocked_before_network(self):
        for method, url, body in [("DELETE", USER, {}), ("POST", DISPLAY, {"username":"x", "role":"patient", "bolus": 1}), ("GET", "https://example.com", {}), ("POST", TOKEN, {"grant_type":"password"})]:
            with self.assertRaises(ValueError): self.transport.request(method, url, data=json.dumps(body) if url == DISPLAY else body)
        self.transport.session.request.assert_not_called()

    def test_refresh_is_authentication_only(self):
        self.transport.post(TOKEN, data={"grant_type":"refresh_token", "refresh_token":"synthetic", "client_id":"synthetic"})
        with self.assertRaises(ValueError): self.transport.post(TOKEN, data={"grant_type":"authorization_code"})

    def test_redirect_blocked(self):
        self.transport.session.request.return_value.status_code = 302
        with self.assertRaises(ValueError): self.transport.get(USER)

    def test_oauth_exact_redirect_and_state(self):
        self.assertEqual(callback_code("carelink://callback?code=abc&state=ok", "carelink://callback", "ok"), "abc")
        self.assertIsNone(callback_code("https://other/?code=abc", "carelink://callback", "ok"))
        with self.assertRaises(ValueError): callback_code("carelink://callback?code=abc&state=no", "carelink://callback", "ok")

    def test_private_storage_and_repo_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "private" / "test.json"
            save_private(path, "synthetic")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(validate_private(path), path.resolve())
            os.chmod(path, 0o644)
            with self.assertRaises(ValueError): validate_private(path)
        with self.assertRaises(ValueError): save_private(ROOT / "secret.json", "synthetic")

    def test_missing_token_never_contacts_network(self):
        with tempfile.TemporaryDirectory() as directory, patch("carelink_proto.client.Transport") as transport:
            with self.assertRaises(ValueError): fetch(Path(directory) / "absent.json")
            transport.assert_not_called()

if __name__ == "__main__":
    unittest.main()


class IntegrationTests(unittest.TestCase):
    def test_upstream_read_and_token_refresh_with_synthetic_responses(self):
        import base64
        import time
        from carelink_proto.security import DISCOVERY, SSO, PATIENTS
        def jwt(expiry):
            claims = {"exp": expiry, "token_details": {"country": "PT", "preferred_username": "synthetic"}}
            encoded = base64.b64encode(json.dumps(claims).encode()).decode().rstrip("=")
            return "synthetic." + encoded + ".synthetic"
        discovery = {"supportedCountries": [{"PT": {"region": "EU"}}], "CP": [{"region": "EU", "UseSSOConfiguration": "auth", "auth": SSO, "baseUrlCareLink": USER.removesuffix("/users/me"), "baseUrlCumulus": DISPLAY.removesuffix("/display/message")}]}
        sso = {"server": {"hostname": "carelink-login.minimed.eu", "port": 443, "prefix": ""}, "system_endpoints": {"token_endpoint_path": "/oauth/token"}}
        calls = []
        def respond(method, url, **kwargs):
            calls.append((method, url))
            if url == DISCOVERY: data = discovery
            elif url == SSO: data = sso
            elif url == USER: data = {"role": "PATIENT"}
            elif url == TOKEN: data = {"access_token": jwt(time.time()+7200), "refresh_token": "new-synthetic"}
            elif url == DISPLAY: data = payload()
            else: raise AssertionError("Unexpected endpoint")
            response = Mock(status_code=200)
            response.json.return_value = data
            return response
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "private" / "token.json"
            save_private(token, json.dumps({"access_token": jwt(0), "refresh_token": "synthetic", "scope": "synthetic", "client_id": "synthetic"}))
            with patch("requests.Session.request", side_effect=respond):
                data = normalize(fetch(token), NOW)
            self.assertEqual(data["glucose"], 112)
            self.assertEqual([method for method, _ in calls], ["GET", "GET", "GET", "POST", "POST"])
            self.assertEqual(json.loads(token.read_text())["refresh_token"], "new-synthetic")
            self.assertEqual(token.stat().st_mode & 0o777, 0o600)

    def test_cli_does_not_print_sensitive_exception(self):
        import io
        from carelink_proto.__main__ import main
        output = io.StringIO()
        with patch("sys.argv", ["carelink_proto", "fetch"]), patch("carelink_proto.client.fetch", side_effect=RuntimeError("SECRET-TOKEN")), patch("sys.stderr", output):
            self.assertEqual(main(), 1)
        self.assertNotIn("SECRET-TOKEN", output.getvalue())

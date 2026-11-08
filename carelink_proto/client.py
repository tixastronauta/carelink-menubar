"""Wrap the pinned upstream reader without running its CLI or proxy."""
import base64
import time
import importlib.util
import json
import logging
from .security import ROOT, STATE, Transport, save_private, validate_private

spec = importlib.util.spec_from_file_location("carelink_upstream", ROOT / "vendor/carelink-python-client/carelink_client2.py")
upstream = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upstream)


class ReadOnlyClient(upstream.CareLinkClient):
    def _read_token_file(self, filename):
        with validate_private(filename).open() as stream:
            data = json.load(stream)
        if not isinstance(data, dict) or not all(isinstance(data.get(k), str) and data[k] for k in ("access_token", "refresh_token", "client_id")):
            raise ValueError("Invalid local token schema.")
        return data

    def _get_access_token_payload(self, token_data):
        # Decoding supplies routing metadata only; the server validates the token.
        try:
            encoded = token_data["access_token"].split(".")[1]
            return json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
        except (KeyError, IndexError, ValueError):
            return None

    def _is_token_valid(self, payload):
        return (isinstance(payload, dict) and isinstance(payload.get("exp"), (int, float))
                and payload["exp"] - time.time() >= 600)

    def _write_token_file(self, obj, filename):
        save_private(filename, json.dumps(obj))

    def _get_patient(self, config, token_data):
        # Never silently select the first person in a follower account.
        response = upstream.requests.get(config["baseUrlCareLink"] + "/links/patients",
                                         headers={"Authorization": "Bearer " + token_data["access_token"]})
        response.raise_for_status()
        patients = response.json()
        if not isinstance(patients, list) or len(patients) != 1:
            raise ValueError("Exactly one linked patient is required for this prototype.")
        return patients[0]


def fetch(token=STATE / "logindata.json"):
    token = validate_private(token)
    upstream.requests = Transport()
    previous = logging.root.manager.disable
    logging.disable(logging.CRITICAL)
    try:
        client = ReadOnlyClient(tokenFile=str(token))
        if not client.init():
            raise ValueError("Authentication failed; no data read. Check account region, MFA and token expiry.")
        data = client.getRecentData()
        if client.getLastResponseCode() != 200 or data is None:
            raise ValueError("CareLink did not return a successful data response.")
        return data
    finally:
        logging.disable(previous)

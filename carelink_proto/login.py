"""Interactive EU Auth0 login, derived from the upstream login flow.

Credentials are entered only in the official web page. Request capture stays in
memory; secrets and authorization URLs are never printed or stored in the repo.
"""
import base64
import hashlib
import json
import logging
import secrets
import tempfile
import time
from pathlib import Path
from urllib.parse import urlencode, urlsplit, parse_qs
from .security import AUTHORIZE, SSO, TOKEN, STATE, Transport, save_private


def callback_code(location, redirect, state):
    actual, expected = urlsplit(location), urlsplit(redirect)
    if (actual.scheme, actual.netloc, actual.path) != (expected.scheme, expected.netloc, expected.path):
        return None
    query = parse_qs(actual.query)
    if query.get("state") != [state] or len(query.get("code", [])) != 1:
        raise ValueError("OAuth callback validation failed.")
    return query["code"][0]


def login():
    if not Path("/Applications/Google Chrome.app").exists():
        raise ValueError("Google Chrome is required for this local prototype login.")
    transport = Transport(login=True)
    config = transport.get(SSO).json()
    if config["server"]["hostname"] != "carelink-login.minimed.eu":
        raise ValueError("Unexpected authentication server.")
    client = config["client"]
    state, verifier = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    params = {"client_id": client["client_id"], "response_type": "code", "scope": client["scope"],
              "redirect_uri": client["redirect_uri"], "audience": client["audience"],
              "state": state, "code_challenge": challenge, "code_challenge_method": "S256"}
    from seleniumwire import webdriver
    previous = logging.root.manager.disable
    logging.disable(logging.CRITICAL)
    driver = None
    try:
        with tempfile.TemporaryDirectory(prefix="carelink-browser-") as temporary:
            options = webdriver.ChromeOptions()
            options.add_argument("--user-data-dir=" + temporary + "/profile")
            driver = webdriver.Chrome(options=options, seleniumwire_options={
                "request_storage": "memory", "request_storage_max_size": 200,
                "request_storage_base_dir": temporary, "verify_ssl": True,
                "addr": "127.0.0.1", "suppress_connection_errors": True})
            driver.get(AUTHORIZE + "?" + urlencode(params))
            deadline = time.monotonic() + 300
            code = None
            while time.monotonic() < deadline and code is None:
                for request in driver.requests:
                    if request.response:
                        location = request.response.headers.get("Location", "")
                        code = callback_code(location, client["redirect_uri"], state)
                        if code: break
                time.sleep(0.2)
            driver.quit()
            driver = None
            if not code:
                raise ValueError("Login timed out. MFA and this account remain unverified.")
            response = transport.post(TOKEN, data={"grant_type": "authorization_code",
                "client_id": client["client_id"], "code": code,
                "redirect_uri": client["redirect_uri"], "code_verifier": verifier})
            response.raise_for_status()
            tokens = response.json()
            if not all(isinstance(tokens.get(k), str) and tokens[k] for k in ("access_token", "refresh_token")):
                raise ValueError("Required tokens were not returned.")
            tokens["client_id"] = client["client_id"]
            save_private(STATE / "logindata.json", json.dumps(tokens))
    finally:
        if driver:
            driver.quit()
        logging.disable(previous)

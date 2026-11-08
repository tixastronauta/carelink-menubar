"""Private local storage and a narrow EU network policy."""
import json
import os
from pathlib import Path
import tempfile
import requests

ROOT = Path(__file__).resolve().parents[1]
STATE = Path.home() / "Library/Application Support/CarelinkPrototype"
DISCOVERY = "https://clcloud.minimed.eu/connect/carepartner/v13/discover/android/3.6"
SSO = "https://carelink.minimed.eu/configs/v1/carepartner_auth0_ous_sso_config_v1.json"
USER = "https://carelink.minimed.eu/api/carepartner/v2/users/me"
PATIENTS = "https://carelink.minimed.eu/api/carepartner/v2/links/patients"
DISPLAY = "https://clcloud.minimed.eu/connect/carepartner/v13/display/message"
TOKEN = "https://carelink-login.minimed.eu/oauth/token"
AUTHORIZE = "https://carelink-login.minimed.eu/authorize"


def outside_repo(path):
    path = Path(path).expanduser().resolve()
    if path == ROOT or ROOT in path.parents:
        raise ValueError("Private files must be outside the project.")
    return path


def save_private(path, data):
    path = outside_repo(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".carelink-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def validate_private(path):
    path = outside_repo(path)
    if not path.is_file():
        raise ValueError("No local token. Run the login command locally first.")
    if path.stat().st_mode & 0o077 or path.parent.stat().st_mode & 0o077:
        raise ValueError("Token permissions must be 600 and directory permissions 700.")
    return path


class Transport:
    """Only observed EU read endpoints and OAuth token exchange are permitted."""
    def __init__(self, login=False):
        self.login = login
        self.session = requests.Session()
        self.session.trust_env = False

    def request(self, method, url, **kwargs):
        url = url.replace("https://carelink-login.minimed.eu:443/", "https://carelink-login.minimed.eu/")
        allowed = method == "GET" and url in {DISCOVERY, SSO, USER, PATIENTS}
        if method == "POST" and url == DISPLAY:
            body = json.loads(kwargs.get("data", "{}"))
            allowed = (set(body) <= {"username", "role", "patientId"}
                       and body.get("role") in {"patient", "carepartner"}
                       and isinstance(body.get("username"), str))
        if method == "POST" and url == TOKEN:
            body = kwargs.get("data", {})
            grants = {"refresh_token", "authorization_code"} if self.login else {"refresh_token"}
            allowed = (isinstance(body, dict) and body.get("grant_type") in grants
                       and set(body) <= {"grant_type", "client_id", "refresh_token", "client_secret", "code", "redirect_uri", "code_verifier"})
        if not allowed:
            raise ValueError("Endpoint or operation blocked by the read-only policy.")
        response = self.session.request(method, url, timeout=(10, 30), allow_redirects=False, **kwargs)
        if 300 <= response.status_code < 400:
            raise ValueError("Unexpected redirect blocked.")
        # The upstream client handles 401/403 and refreshes once.
        if response.status_code not in {401, 403}:
            response.raise_for_status()
        return response

    def get(self, url, **kwargs):
        return self.request("GET", url, **kwargs)

    def post(self, url, **kwargs):
        return self.request("POST", url, **kwargs)

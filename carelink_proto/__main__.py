"""Local command-line entry point. No credentials accepted as arguments."""
import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from .model import normalize
from .chart import render
from .security import STATE, save_private


def demo_payload():
    now = datetime.now(timezone.utc).replace(microsecond=0)
    return {"patientData": {"bgUnits": "MGDL", "lastSGTrend": "NONE",
        "lastSG": {"sg": 112, "datetime": now.isoformat()},
        "activeInsulin": {"amount": 1.2, "datetime": now.isoformat()},
        "sgs": [{"sg": 100 + i % 23, "datetime": (now - timedelta(minutes=5 * (35-i))).isoformat()} for i in range(36)]}}


def main():
    parser = argparse.ArgumentParser(description="Experimental EU CareLink read-only prototype")
    parser.add_argument("command", choices=["demo", "fetch", "login"])
    args = parser.parse_args()
    try:
        if args.command == "login":
            print("Enter credentials only in the official CareLink browser page. Login timeout: 5 minutes.")
            from .login import login
            login()
            print("Login saved privately outside the project. No pump data requested.")
            return 0
        if args.command == "fetch":
            from .client import fetch
            raw = fetch()
        else:
            raw = demo_payload()
        data = normalize(raw)
        data["synthetic"] = args.command == "demo"
        name = "demo" if data["synthetic"] else "snapshot"
        save_private(STATE / (name + ".json"), json.dumps(data, indent=2, allow_nan=False))
        save_private(STATE / (name + ".html"), render(data, data["synthetic"]))
        print(f"Saved {name}.json and {name}.html in {STATE}")
        print(f"History points: {len(data['history'])}. Flex compatibility: unverified.")
        return 0
    except Exception:
        # Exception text may contain tokens, payloads, browser URLs or identities.
        print("Operation failed. No sensitive details logged. See docs/DIAGNOSTIC.md for local checks.", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())

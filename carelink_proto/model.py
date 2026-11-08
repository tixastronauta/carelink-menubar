"""Conservative normalization of the documented CareLink payload."""
from datetime import datetime, timezone
import math
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def number(value, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if not math.isfinite(value) or value < 0 or (positive and value == 0):
        return None
    return value


def timestamp(value, zone=None):
    if not isinstance(value, str):
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            if not isinstance(zone, str):
                return None
            tz = ZoneInfo(zone)
            candidates = []
            for fold in (0, 1):
                aware = dt.replace(tzinfo=tz, fold=fold)
                utc = aware.astimezone(timezone.utc)
                if utc.astimezone(tz).replace(tzinfo=None) == dt:
                    candidates.append(utc)
            # Do not guess during the repeated or missing DST hour.
            if len(set(candidates)) != 1:
                return None
            dt = candidates[0]
        return dt.astimezone(timezone.utc).isoformat()
    except (ValueError, ZoneInfoNotFoundError):
        return None


def normalize(raw, now=None):
    if not isinstance(raw, dict):
        raise ValueError("Unrecognized response schema.")
    data = raw.get("patientData", raw)
    if not isinstance(data, dict) or not any(k in data for k in ("lastSG", "sgs", "activeInsulin")):
        raise ValueError("Unrecognized response schema; Flex support remains unverified.")
    warnings = []
    unit = {"MGDL": "mg/dL", "MMOLL": "mmol/L", "mg/dL": "mg/dL", "mmol/L": "mmol/L"}.get(data.get("bgUnits"))
    if not unit:
        warnings.append("Glucose unit unavailable; do not infer or convert it.")
    last = data.get("lastSG") or {}
    insulin = data.get("activeInsulin") or {}
    if not isinstance(last, dict): last = {}
    if not isinstance(insulin, dict): insulin = {}
    zone = data.get("clientTimeZoneName")
    stamp = timestamp(last.get("timestamp"), zone) or timestamp(last.get("datetime"), zone) or timestamp(data.get("lastSGDateTime")) or timestamp(data.get("sLastSensorTime")) or timestamp(data.get("lastSensorTSAsString"))
    glucose = number(last.get("sg"), positive=True)
    now = now or datetime.now(timezone.utc)
    age = (now - datetime.fromisoformat(stamp)).total_seconds() if stamp else None
    stale = age is None or age > 900 or age < -300
    if stale: warnings.append("Reading stale, timestamp missing, or clock mismatch.")
    if glucose is None: warnings.append("Current glucose unavailable or invalid.")
    points = {}
    invalid = 0
    history = data.get("sgs") or []
    if not isinstance(history, list): history = []
    for item in history:
        if not isinstance(item, dict):
            invalid += 1
            continue
        t, v = (timestamp(item.get("timestamp"), zone) or timestamp(item.get("datetime"), zone)), number(item.get("sg"), positive=True)
        if t and v is not None: points[t] = v
        else: invalid += 1
    if invalid: warnings.append(f"Excluded {invalid} invalid history records.")
    if not points: warnings.append("No usable history supplied by the server.")
    trend = data.get("lastSGTrend")
    if trend not in {"NONE", "UP", "UP_DOUBLE", "UP_TRIPLE", "DOWN", "DOWN_DOUBLE", "DOWN_TRIPLE"}:
        trend = None
    return {"glucose": glucose, "unit": unit, "timestamp": stamp, "trend": trend,
            "active_insulin_units": number(insulin.get("amount")),
            "active_insulin_timestamp": timestamp(insulin.get("timestamp"), zone) or timestamp(insulin.get("datetime"), zone),
            "age_seconds": round(age) if age is not None else None, "stale": stale,
            "history": [{"timestamp": t, "glucose": v} for t, v in sorted(points.items())],
            "warnings": warnings, "flex_compatibility": "unverified"}

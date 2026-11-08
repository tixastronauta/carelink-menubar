"""Generate a static offline chart without third-party scripts or telemetry."""
from datetime import datetime
from html import escape


def render(data, demo=False):
    def text(value):
        return escape(str(value if value is not None else "Unavailable"))
    points = data["history"]
    circles = []
    if points and data["unit"]:
        times = [datetime.fromisoformat(p["timestamp"]).timestamp() for p in points]
        values = [p["glucose"] for p in points]
        lo, hi = min(values) - 10, max(values) + 10
        for t, v in zip(times, values):
            x = 60 + (t - min(times)) / max(1, max(times) - min(times)) * 800
            y = 240 - (v - lo) / (hi - lo) * 200
            circles.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="3"><title>{v} at {datetime.fromtimestamp(t).astimezone().isoformat()}</title></circle>')
        label = f'{text(round(lo, 1))}–{text(round(hi, 1))} {text(data["unit"])} · {text(points[0]["timestamp"])} → {text(points[-1]["timestamp"])}'
    else:
        label = "Chart unavailable: history or glucose units missing."
    warnings = " ".join(data["warnings"])
    return f'''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>CareLink local prototype</title><style>
body{{font:18px system-ui;background:#f4f6fa;color:#172a3a;max-width:1000px;margin:50px auto;padding:20px}}
section{{background:white;border-radius:16px;padding:24px;margin:20px 0}}svg{{width:100%;fill:#176caa}}
.notice{{color:#8b3600}}small{{color:#455a68}}
</style><h1>CareLink · local prototype</h1>
<p class="notice">{"DEMO — SYNTHETIC DATA" if demo else "EXPERIMENTAL — CLOUD SNAPSHOT"} · Not for treatment decisions.</p>
<section><h2>{text(data["glucose"])} {text(data["unit"])}</h2>
<p>Sensor timestamp: {text(data["timestamp"])} · Trend: {text(data["trend"])}</p>
<p>Active insulin reported by server: {text(data["active_insulin_units"])} U</p>
<p>Active insulin timestamp: {text(data["active_insulin_timestamp"])}</p>
<p class="notice">{text(warnings)}</p></section>
<section><h2>Available glucose history</h2><svg viewBox="0 0 920 280" role="img" aria-label="Glucose history scatter chart">{"".join(circles)}</svg><small>{label}</small></section>
<p>Static snapshot. It does not refresh automatically. Flex compatibility remains unverified.</p></html>'''

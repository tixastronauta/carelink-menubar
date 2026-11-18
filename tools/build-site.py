#!/usr/bin/env python3
"""Builds the website: one static page per language from site/index.html and site/i18n/*.json.

    python3 tools/build-site.py [output]   # default: build/site

Output: index.html (English), pt/index.html (Portuguese), robots.txt, sitemap.xml and the assets
(icon, screenshots, social cards). Static pages per language let link previews and search engines,
which do not run JavaScript, see the right language. Fails on a missing or unused key.
"""
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE_URL = "https://tixastronauta.github.io/carelink-menubar/"
# code -> (output folder, html lang, Open Graph locale, alternate locale, screenshot suffix)
LANGUAGES = {
    "en": ("", "en", "en_GB", "pt_PT", ""),
    "pt": ("pt/", "pt-PT", "pt_PT", "en_GB", "-pt"),
}
PLACEHOLDER = re.compile(r"\{\{([A-Za-z0-9_.]+)\}\}")


def load(code):
    return json.loads((ROOT / "site" / "i18n" / f"{code}.json").read_text(encoding="utf-8"))


def render(template, code, strings):
    folder, lang, locale, alternate, shot = LANGUAGES[code]
    values = dict(strings)
    values.update({
        "root": "../" if folder else "",
        "shot": shot,
        "site.url": SITE_URL,
        "page.url": SITE_URL + folder,
        "page.code": code,
        "page.lang": lang,
        "page.locale": locale,
        "page.altLocale": alternate,
        "page.enCurrent": 'aria-current="page"' if code == "en" else "",
        "page.ptCurrent": 'aria-current="page"' if code == "pt" else "",
    })
    used = set()

    def replace(match):
        key = match.group(1)
        if key not in values:
            raise SystemExit(f"{code}: missing key {key}")
        used.add(key)
        return values[key]

    html = PLACEHOLDER.sub(replace, template)
    unused = set(strings) - used
    if unused:
        raise SystemExit(f"{code}: unused keys {sorted(unused)}")
    return html


def build(out):
    template = (ROOT / "site" / "index.html").read_text(encoding="utf-8")
    dictionaries = {code: load(code) for code in LANGUAGES}
    keys = {code: set(strings) for code, strings in dictionaries.items()}
    if keys["en"] != keys["pt"]:
        raise SystemExit(f"en/pt keys differ: {sorted(keys['en'] ^ keys['pt'])}")
    for code, strings in dictionaries.items():
        # meta.* values go into attributes and JSON-LD verbatim.
        for key, value in strings.items():
            if key.startswith("meta.") and re.search(r'["<>\\]', value):
                raise SystemExit(f"{code}: {key} must not contain quotes, angle brackets or backslashes")
    if out.exists():
        shutil.rmtree(out)
    for code, strings in dictionaries.items():
        page = out / LANGUAGES[code][0] / "index.html"
        page.parent.mkdir(parents=True, exist_ok=True)
        page.write_text(render(template, code, strings), encoding="utf-8")
    (out / "assets").mkdir(parents=True, exist_ok=True)
    shutil.copy(ROOT / "assets" / "AppIcon-1024.png", out / "assets")
    shutil.copytree(ROOT / "assets" / "screenshots", out / "assets" / "screenshots")
    (out / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {SITE_URL}sitemap.xml\n")
    links = "".join(
        f'\n    <xhtml:link rel="alternate" hreflang="{"pt" if c == "pt" else "en"}" href="{SITE_URL}{LANGUAGES[c][0]}"/>'
        for c in LANGUAGES) + f'\n    <xhtml:link rel="alternate" hreflang="x-default" href="{SITE_URL}"/>'
    urls = "".join(f"\n  <url>\n    <loc>{SITE_URL}{LANGUAGES[c][0]}</loc>{links}\n  </url>" for c in LANGUAGES)
    (out / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">'
        f"{urls}\n</urlset>\n")
    return out


if __name__ == "__main__":
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "site"
    print(f"wrote {build(target.resolve())}")

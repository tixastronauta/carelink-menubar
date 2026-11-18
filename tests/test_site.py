"""Tests for tools/build-site.py (website build). Offline; writes to a temporary folder."""
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("build_site", ROOT / "tools" / "build-site.py")
build_site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_site)
URL = build_site.SITE_URL


class BuildSiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = build_site.build(Path(cls.tmp.name) / "site")
        cls.en = (cls.out / "index.html").read_text(encoding="utf-8")
        cls.pt = (cls.out / "pt" / "index.html").read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def meta(self, html, attr, name):
        match = re.search(rf'<meta {attr}="{re.escape(name)}" content="([^"]*)">', html)
        self.assertIsNotNone(match, name)
        return match.group(1)

    def test_no_placeholders_left(self):
        for html in (self.en, self.pt):
            self.assertNotIn("{{", html)

    def test_languages_and_canonical(self):
        self.assertIn('<html lang="en">', self.en)
        self.assertIn('<html lang="pt-PT">', self.pt)
        self.assertIn(f'<link rel="canonical" href="{URL}">', self.en)
        self.assertIn(f'<link rel="canonical" href="{URL}pt/">', self.pt)
        for html in (self.en, self.pt):
            self.assertIn(f'hreflang="pt" href="{URL}pt/"', html)
            self.assertIn(f'hreflang="x-default" href="{URL}"', html)

    def test_share_previews_are_static_and_absolute(self):
        self.assertEqual(self.meta(self.en, "property", "og:image"), f"{URL}assets/screenshots/social-card.png")
        self.assertEqual(self.meta(self.pt, "property", "og:image"), f"{URL}assets/screenshots/social-card-pt.png")
        self.assertEqual(self.meta(self.pt, "property", "og:locale"), "pt_PT")
        self.assertEqual(self.meta(self.pt, "name", "twitter:card"), "summary_large_image")
        self.assertIn("glicemia", self.meta(self.pt, "property", "og:title"))
        for name in ("social-card.png", "social-card-pt.png", "panel-dark-pt.png"):
            self.assertTrue((self.out / "assets" / "screenshots" / name).exists(), name)

    def test_portuguese_page_is_translated_and_uses_parent_assets(self):
        self.assertIn("A tua glicemia", self.pt)
        self.assertIn('src="../assets/screenshots/panel-dark-pt.png"', self.pt)
        self.assertIn('src="assets/screenshots/panel-dark.png"', self.en)
        self.assertIn('data-lang="pt" title="Português" aria-current="page"', self.pt)

    def test_structured_data_is_valid_json(self):
        for html in (self.en, self.pt):
            block = re.search(r'<script type="application/ld\+json">(.*?)</script>', html, re.S).group(1)
            self.assertEqual(json.loads(block)["@type"], "SoftwareApplication")

    def test_sitemap_and_robots(self):
        tree = ET.parse(self.out / "sitemap.xml")
        locs = [e.text for e in tree.iter("{http://www.sitemaps.org/schemas/sitemap/0.9}loc")]
        self.assertEqual(locs, [URL, URL + "pt/"])
        self.assertIn(f"Sitemap: {URL}sitemap.xml", (self.out / "robots.txt").read_text())


if __name__ == "__main__":
    unittest.main()

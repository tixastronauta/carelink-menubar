"""Synthetic tests for tools/appcast.py (in-app update feed). No network, no keys."""
import contextlib
from datetime import datetime, timezone
import io
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import appcast  # noqa: E402

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
HISTORY = """# History

## 0.3.3: in-app updates

- **Updates:** the app checks for new versions
  once a day and installs them on request.
- Uses `Sparkle` <signed> & [verified](https://sparkle-project.org).

## 0.3.2: lighter widget

- Older entry.
"""


class BuildNumberTests(unittest.TestCase):
    def test_monotonic_numbers(self):
        self.assertEqual(appcast.build_number("0.3.2"), "302")
        self.assertEqual(appcast.build_number("0.3.3"), "303")
        self.assertEqual(appcast.build_number("1.2.10"), "10210")
        versions = ["0.3.3", "0.3.10", "0.4.0", "1.0.0"]
        numbers = [int(appcast.build_number(v)) for v in versions]
        self.assertEqual(numbers, sorted(numbers))
        # Above the constant "3" that 0.3.2 and earlier shipped with.
        self.assertGreater(numbers[0], 3)

    def test_rejects_bad_versions(self):
        for bad in ("0.3", "0.3.3-beta", "0.100.0", "0.3.100"):
            with self.assertRaises(ValueError):
                appcast.build_number(bad)


class NotesTests(unittest.TestCase):
    def test_section_for_version_only(self):
        notes = appcast.release_notes(HISTORY, "0.3.3")
        self.assertIn("installs them on request", notes)
        self.assertNotIn("Older entry", notes)
        self.assertIn("Older entry", appcast.release_notes(HISTORY, "0.3.2"))
        with self.assertRaises(ValueError):
            appcast.release_notes(HISTORY, "9.9.9")

    def test_markdown_subset_is_escaped(self):
        rendered = appcast.markdown_to_html(appcast.release_notes(HISTORY, "0.3.3"))
        self.assertIn("<li><strong>Updates:</strong> the app checks for new versions once a day", rendered)
        self.assertIn("<code>Sparkle</code> &lt;signed&gt; &amp;", rendered)
        self.assertIn('<a href="https://sparkle-project.org">verified</a>', rendered)
        self.assertEqual(rendered.count("<ul>"), 1)


class AppcastTests(unittest.TestCase):
    def test_sign_output_parsing(self):
        signature, length = appcast.parse_sign_output('sparkle:edSignature="c2lnbmF0dXJl==" length="1234"\n')
        self.assertEqual((signature, length), ("c2lnbmF0dXJl==", 1234))
        with self.assertRaises(ValueError):
            appcast.parse_sign_output("error: no key")

    def test_feed_item(self):
        xml = appcast.appcast("0.3.3", "https://example.invalid/CareLink-Menubar.zip", "c2ln", 42,
                              "<p>notes ]]> end</p>", datetime(2026, 11, 10, 12, tzinfo=timezone.utc))
        item = ET.fromstring(xml).find("channel/item")
        self.assertEqual(item.find(f"{SPARKLE}version").text, "303")
        self.assertEqual(item.find(f"{SPARKLE}shortVersionString").text, "0.3.3")
        self.assertEqual(item.find(f"{SPARKLE}minimumSystemVersion").text, "14.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://example.invalid/CareLink-Menubar.zip")
        self.assertEqual(enclosure.get("length"), "42")
        self.assertEqual(enclosure.get(f"{SPARKLE}edSignature"), "c2ln")
        # A CDATA terminator inside the notes must not break the feed.
        self.assertIn("notes ]]> end", item.find("description").text)
        self.assertIn("Tue, 10 Nov 2026 12:00:00", item.find("pubDate").text)

    def test_cli_rejects_insecure_urls(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            appcast.main(["--version", "0.3.3", "--url", "http://example.invalid/a.zip",
                          "--sign-output", 'sparkle:edSignature="x" length="1"', "--history", "/dev/null"])


if __name__ == "__main__":
    unittest.main()

"""Release helpers for in-app updates (Sparkle), shared by tools/build-menubar.py and the release
workflow. Standard library only.

Writes the appcast for one release: a single <item> for the newest version, published as the
release asset appcast.xml, so https://github.com/<repo>/releases/latest/download/appcast.xml always
describes the latest release. The release notes are the version's section of docs/HISTORY.md.

    python3 tools/appcast.py --version 0.3.3 --url <zip url> --sign-output "<sign_update output>" \\
        --history docs/HISTORY.md > build/appcast.xml

The workflow then signs the appcast itself with sign_update (the app requires a signed feed).
"""
import argparse
import html
import re
import sys
from datetime import datetime, timezone
from email.utils import format_datetime

MINIMUM_SYSTEM = "14.0"


def build_number(version):
    """Monotonic CFBundleVersion that Sparkle compares: 0.3.3 -> 303, 1.2.10 -> 10210."""
    parts = version.split(".")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ValueError(f"version must be MAJOR.MINOR.PATCH: {version!r}")
    major, minor, patch = (int(part) for part in parts)
    if minor >= 100 or patch >= 100:
        raise ValueError(f"minor and patch must be below 100: {version!r}")
    return str(major * 10000 + minor * 100 + patch)


def release_notes(history, version):
    """Body of the '## <version>...' section of docs/HISTORY.md (up to the next '## ')."""
    match = re.search(rf"^## {re.escape(version)}\b[^\n]*\n(.*?)(?=^## |\Z)", history, re.M | re.S)
    if not match:
        raise ValueError(f"docs/HISTORY.md has no '## {version}' section")
    return match.group(1).strip()


def _inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"\[([^\]]+)\]\((https://[^)\s]+)\)", r'<a href="\2">\1</a>', text)


def markdown_to_html(markdown):
    """The small Markdown subset used in HISTORY.md: paragraphs and '- ' bullets (continuation
    lines indented), with **bold**, `code` and https links. Everything else is escaped."""
    blocks, items, paragraph = [], [], []

    def flush_paragraph():
        if paragraph:
            blocks.append(f"<p>{_inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def flush_items():
        if items:
            blocks.append("<ul>" + "".join(f"<li>{_inline(item)}</li>" for item in items) + "</ul>")
            items.clear()

    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped:
            flush_paragraph(); flush_items()
        elif stripped.startswith("- "):
            flush_paragraph(); items.append(stripped[2:])
        elif items and line.startswith(" "):
            items[-1] += " " + stripped
        else:
            flush_items(); paragraph.append(stripped)
    flush_paragraph(); flush_items()
    return "\n".join(blocks)


def parse_sign_output(output):
    """sign_update prints: sparkle:edSignature="..." length="..."."""
    signature = re.search(r'sparkle:edSignature="([^"]+)"', output)
    length = re.search(r'length="(\d+)"', output)
    if not signature or not length:
        raise ValueError("unexpected sign_update output")
    return signature.group(1), int(length.group(1))


def appcast(version, url, signature, length, notes_html, published=None):
    """RSS appcast with one item. Sparkle compares sparkle:version (the build number)."""
    published = published or datetime.now(timezone.utc)
    title = f"CareLink Menubar {version}"
    notes = notes_html.replace("]]>", "]]]]><![CDATA[>")
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>CareLink Menubar</title>
    <item>
      <title>{html.escape(title)}</title>
      <pubDate>{format_datetime(published)}</pubDate>
      <sparkle:version>{build_number(version)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MINIMUM_SYSTEM}</sparkle:minimumSystemVersion>
      <description><![CDATA[<h2>{html.escape(title)}</h2>
{notes}]]></description>
      <enclosure url="{html.escape(url)}" length="{int(length)}" type="application/octet-stream" sparkle:edSignature="{html.escape(signature)}"/>
    </item>
  </channel>
</rss>
"""


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True, help="https URL of the signed update archive")
    parser.add_argument("--sign-output", required=True, help="output of sign_update for the archive")
    parser.add_argument("--history", required=True, help="docs/HISTORY.md")
    args = parser.parse_args(argv)
    if not args.url.startswith(("https://", "http://localhost", "http://127.0.0.1")):
        parser.error("the update URL must use https (or localhost, for local tests)")
    signature, length = parse_sign_output(args.sign_output)
    with open(args.history, encoding="utf-8") as handle:
        notes = markdown_to_html(release_notes(handle.read(), args.version))
    sys.stdout.write(appcast(args.version, args.url, signature, length, notes))


if __name__ == "__main__":
    main()

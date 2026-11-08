"""Check that every tr("...") key used in macos/ has an English entry in Localization.swift.

Usage: python3 tools/check-translations.py  (exit code 1 when a key is missing)
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
source = (root / "macos" / "Localization.swift").read_text()
english = source[source.index("static let english"):source.index("static let portugueseInfo")]
portuguese_info = source[source.index("static let portugueseInfo"):]
english_keys = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)":', english, re.M))
identifier = re.compile(r"^[a-z]+\.[a-z]+$")  # info.*, consent.*: need both languages
info_keys = set(re.findall(r'^\s*"([a-z]+\.[a-z]+)":', portuguese_info, re.M))

# Matches tr("key") and tr(condition ? "a" : "b"), plus addPane("key", ...) titles.
pattern = re.compile(r'(?:tr|addPane)\(\s*(?:[^"()]*\?\s*)?"((?:[^"\\]|\\.)*)"(?:\s*:\s*"((?:[^"\\]|\\.)*)")?')
used = set()
for path in (root / "macos").glob("*.swift"):
    if path.name == "Localization.swift" or path.name.endswith("Checks.swift"):
        continue
    for match in pattern.finditer(path.read_text()):
        used.update(group for group in match.groups() if group)

missing = sorted(key for key in used if key not in english_keys)
missing_info = sorted(key for key in (used | {k for k in english_keys if identifier.match(k)}) if identifier.match(key) and key not in info_keys)
unused = sorted(key for key in english_keys if key not in used)
print(f"{len(used)} keys used; {len(missing)} missing English; {len(missing_info)} missing Portuguese info")
for key in missing + missing_info:
    print("  missing:", key)
if unused:
    print("unused English keys:", ", ".join(unused))
sys.exit(1 if missing or missing_info else 0)

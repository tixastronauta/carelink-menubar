"""Build a standalone universal app. Build-time Python is not bundled or required to run it.

    python3 tools/build-menubar.py            development variant -> build/CareLink Menubar Dev.app
    python3 tools/build-menubar.py --release  release variant     -> build/CareLink Menubar.app

The development variant has its own bundle ID, icon, Keychain session, App Group, URL scheme and
logs, so it runs beside the installed release, and it never updates itself. Only the release
variant carries the Sparkle feed and public key (see docs/GUIDE.md, "In-app updates").
Environment: CARELINK_SIGN_IDENTITY (signing identity), CARELINK_VERSION (override the version,
for update tests), CARELINK_TEST_FEED_URL (point a build at a test appcast; enables updates in
the development variant too, for local end-to-end update tests only).
"""
from pathlib import Path
import hashlib
import plistlib
import subprocess
import sys
import os
import tarfile
import urllib.request

VERSION = "0.3.3"
SPARKLE_VERSION = "2.10.1"
SPARKLE_SHA256 = "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
# EdDSA public key matching the private key in the release workflow secret SPARKLE_ED_PRIVATE_KEY
# (and in the maintainer's login Keychain, account "carelink-menubar"). Changing it strands every
# installed copy: they would reject updates signed with the new key.
SPARKLE_PUBLIC_KEY = "T6RmOkOVMMau+wUcmNn91pD4aQGxIs8pOcgXXzXF/PE="
# The newest release's appcast, published as a release asset by .github/workflows/release.yml.
FEED_URL = "https://github.com/tixastronauta/carelink-menubar/releases/latest/download/appcast.xml"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from appcast import build_number  # noqa: E402  (shared with the release workflow and tests)

release = "--release" in sys.argv[1:]
variant = "release" if release else "dev"
version = os.environ.get("CARELINK_VERSION") or VERSION
test_feed = os.environ.get("CARELINK_TEST_FEED_URL")
display_name = "CareLink Menubar" if release else "CareLink Menubar Dev"
bundle_id = "local.tcx.carelink.menu" if release else "local.tcx.carelink.menu.dev"
url_scheme = "carelinkmenu" if release else "carelinkmenu-dev"

root = Path(__file__).resolve().parents[1]
build = root / "build"
app = build / f"{display_name}.app"
contents = app / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
resources = contents / "Resources"
resources.mkdir(exist_ok=True)
import re

def sparkle_framework():
    """Sparkle's release archive, downloaded once into build/deps and checked against the pinned hash."""
    folder = build / "deps" / f"Sparkle-{SPARKLE_VERSION}"
    if not (folder / "Sparkle.framework").exists():
        folder.mkdir(parents=True, exist_ok=True)
        archive = folder.parent / f"Sparkle-{SPARKLE_VERSION}.tar.xz"
        url = f"https://github.com/sparkle-project/Sparkle/releases/download/{SPARKLE_VERSION}/Sparkle-{SPARKLE_VERSION}.tar.xz"
        urllib.request.urlretrieve(url, archive)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != SPARKLE_SHA256:
            archive.unlink()
            sys.exit(f"Sparkle archive hash mismatch: {digest}")
        subprocess.run(["tar", "-xf", str(archive), "-C", str(folder)], check=True)
        archive.unlink()
    return folder
sparkle = sparkle_framework()
def default_identity():
    # Prefer an identity with a Team ID: Keychain "Always Allow" then survives rebuilds.
    # Without one (ad-hoc), approval is tied to the cdhash of each build.
    found = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                           capture_output=True, text=True).stdout.splitlines()
    for line in found:
        if '"Apple Development:' in line:
            return line.split()[1]  # SHA-1 hash avoids ambiguous names
    return "-"
identity = os.environ.get("CARELINK_SIGN_IDENTITY") or default_identity()

def team_id(identity):
    """Team ID the signature will carry (needed to prefix the App Group shared with the widget).
    The ID in parentheses in an "Apple Development: Name (XXXXXXXXXX)" certificate name is a
    personal ID, not the Team ID, so sign a scratch binary and read TeamIdentifier instead."""
    if identity == "-":
        return None
    scratch = build / "team-id-probe"
    subprocess.run(["cp", "/usr/bin/true", str(scratch)], check=True)
    subprocess.run(["codesign", "--force", "--sign", identity, str(scratch)], check=True, capture_output=True)
    details = subprocess.run(["codesign", "-dv", str(scratch)], capture_output=True, text=True).stderr
    scratch.unlink()
    match = re.search(r"^TeamIdentifier=([A-Z0-9]{10})$", details, re.M)
    return match.group(1) if match else None
team = team_id(identity)
app_group = f"{team}.{bundle_id}" if team else None

info = {
    "CFBundleName": display_name, "CFBundleDisplayName": display_name,
    "CFBundleIdentifier": bundle_id, "CFBundleVersion": build_number(version),
    "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL",
    "CFBundleExecutable": "CareLinkMenubar", "LSUIElement": True,
    "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": True,
    "CFBundleIconFile": "AppIcon",
    # Lets Sparkle's windows use its Portuguese (Portugal) strings; the app follows its own setting.
    "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "pt-PT"],
    # carelinkmenu://open (carelinkmenu-dev:// in development) is used by the widget to open the panel.
    "CFBundleURLTypes": [{"CFBundleURLName": bundle_id, "CFBundleURLSchemes": [url_scheme]}],
    "CareLinkVariant": variant,
}
if app_group:
    info["CareLinkAppGroup"] = app_group
if release or test_feed:
    # Sparkle: daily background checks, on by default; no system profile is ever sent.
    info.update({"SUFeedURL": test_feed or FEED_URL, "SUPublicEDKey": SPARKLE_PUBLIC_KEY,
                 "SUEnableAutomaticChecks": True, "SUScheduledCheckInterval": 86400,
                 "SUEnableSystemProfiling": False,
                 # The workflow signs appcast.xml too; unsigned or tampered feeds are rejected.
                 "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True})
if test_feed:
    info["CareLinkTestFeed"] = True
    if test_feed.startswith("http://"):
        info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
(contents / "Info.plist").write_bytes(plistlib.dumps(info))
(resources / "LICENSE").write_bytes((root / "LICENSE").read_bytes())
# App icon generated by tools/make-icon.swift (committed so builds do not need to redraw it).
(resources / "AppIcon.icns").write_bytes((root / "assets" / ("AppIcon.icns" if release else "AppIcon-Dev.icns")).read_bytes())
(resources / "NOTICE.txt").write_text(f"CareLink Menubar {version} — AGPL-3.0\nProtocol compatibility derived from ondrej1024/carelink-python-client, commit 29051ca9944cc65042c780bef22433629aa9e367.\nOriginal client copyright Ondrej Wisniewski and contributors; authentication work credits Pal Marci and m0rt4l1n.\nhttps://github.com/ondrej1024/carelink-python-client\nCorresponding source and build script: Source.tar.gz in this folder and https://github.com/tixastronauta/carelink-menubar\nUnofficial application; not affiliated with MiniMed (formerly Medtronic Diabetes).\nIn-app updates: Sparkle {SPARKLE_VERSION} (https://sparkle-project.org), MIT licence; full text in Sparkle-LICENSE.txt.\n")
(resources / "Sparkle-LICENSE.txt").write_bytes((sparkle / "LICENSE").read_bytes())
sources = [root / "macos" / name for name in ("AppVariant.swift", "Updates.swift", "WidgetShared.swift", "Localization.swift", "Model.swift", "NativeCore.swift", "Diagnostics.swift", "CredentialVault.swift", "NativeAPI.swift", "WebLogin.swift", "LaunchAtLogin.swift", "Store.swift", "Preferences.swift", "Notifications.swift", "Consent.swift", "SettingsView.swift", "PopoverView.swift", "App.swift")]
for arch in ("arm64", "x86_64"):
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-O", "-target", arch + "-apple-macos14.0",
        "-module-cache-path", str(build / "module-cache"), "-F", str(sparkle), "-framework", "Sparkle",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", *map(str, sources),
        "-o", str(build / ("CareLinkMenubar-" + arch))], check=True)
subprocess.run(["lipo", "-create", str(build / "CareLinkMenubar-arm64"), str(build / "CareLinkMenubar-x86_64"),
    "-output", str(contents / "MacOS" / "CareLinkMenubar")], check=True)
with tarfile.open(resources / "Source.tar.gz", "w:gz") as archive:
    for folder in ("macos", "tools"):
        for path in sorted((root / folder).glob("*")):
            if path.is_file() and path.suffix in {".swift", ".py", ".sh"}:
                archive.add(path, arcname=str(path.relative_to(root)))
    archive.add(root / "LICENSE", arcname="LICENSE")
    for doc in ("README.md", "docs/GUIDE.md"):
        if (root / doc).exists(): archive.add(root / doc, arcname=doc)
command = ["codesign", "--force", "--sign", identity]
if identity != "-": command += ["--options", "runtime"]
if identity.startswith("Developer ID"): command += ["--timestamp"]

# Sparkle.framework in Contents/Frameworks, signed inside-out with our identity (Sparkle's
# documented order for apps signed outside Xcode; never --deep).
frameworks = contents / "Frameworks"
subprocess.run(["rm", "-rf", str(frameworks)], check=True)
frameworks.mkdir()
subprocess.run(["ditto", str(sparkle / "Sparkle.framework"), str(frameworks / "Sparkle.framework")], check=True)
sparkle_b = frameworks / "Sparkle.framework" / "Versions" / "B"
subprocess.run(command + [str(sparkle_b / "XPCServices" / "Installer.xpc")], check=True)
subprocess.run(command + ["--preserve-metadata=entitlements", str(sparkle_b / "XPCServices" / "Downloader.xpc")], check=True)
subprocess.run(command + [str(sparkle_b / "Autoupdate")], check=True)
subprocess.run(command + [str(sparkle_b / "Updater.app")], check=True)
subprocess.run(command + [str(frameworks / "Sparkle.framework")], check=True)

# Widget extension (WidgetKit). Needs a Team ID for the App Group, so it is skipped ad-hoc.
plugins = contents / "PlugIns"
if plugins.exists():
    subprocess.run(["rm", "-rf", str(plugins)], check=True)
if app_group:
    appex = plugins / "CareLinkWidget.appex" / "Contents"
    (appex / "MacOS").mkdir(parents=True, exist_ok=True)
    widget_info = {
        "CFBundleName": "CareLinkWidget", "CFBundleDisplayName": "CareLink" if release else "CareLink Dev",
        # Unique build number per build: the widget gallery caches the supported sizes and
        # description per bundle version and would otherwise keep showing an old build.
        "CFBundleIdentifier": f"{bundle_id}.widget",
        "CFBundleVersion": f'{info["CFBundleVersion"]}.{int(__import__("time").time())}',
        "CFBundleShortVersionString": info["CFBundleShortVersionString"], "CFBundlePackageType": "XPC!",
        "CFBundleExecutable": "CareLinkWidget", "LSMinimumSystemVersion": "14.0",
        "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
        "CFBundleInfoDictionaryVersion": "6.0", "CFBundleDevelopmentRegion": "en",
        "CFBundleSupportedPlatforms": ["MacOSX"],
        "CareLinkAppGroup": app_group, "CareLinkVariant": variant,
    }
    (appex / "Info.plist").write_bytes(plistlib.dumps(widget_info))
    widget_sources = [root / "macos" / name for name in ("AppVariant.swift", "Localization.swift", "Model.swift", "WidgetShared.swift", "WidgetExtension.swift")]
    for arch in ("arm64", "x86_64"):
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-O", "-parse-as-library", "-application-extension",
            "-target", arch + "-apple-macos14.0", "-module-cache-path", str(build / "module-cache"),
            # Extensions start in _NSExtensionMain (as Xcode links them), not the Swift main.
            "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain",
            *map(str, widget_sources), "-o", str(build / ("CareLinkWidget-" + arch))], check=True)
    subprocess.run(["lipo", "-create", str(build / "CareLinkWidget-arm64"), str(build / "CareLinkWidget-x86_64"),
        "-output", str(appex / "MacOS" / "CareLinkWidget")], check=True)
    widget_entitlements = build / "widget.entitlements"
    widget_entitlements.write_bytes(plistlib.dumps({
        "com.apple.security.app-sandbox": True,
        "com.apple.security.application-groups": [app_group]}))
    subprocess.run(command + ["--entitlements", str(widget_entitlements), str(appex.parent)], check=True)
    app_entitlements = build / "app.entitlements"
    app_entitlements.write_bytes(plistlib.dumps({"com.apple.security.application-groups": [app_group]}))
    command += ["--entitlements", str(app_entitlements)]
else:
    print("No Team ID: widget extension skipped (needs an Apple Development or Developer ID identity).")
subprocess.run(command + [str(app)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
# macOS keeps the old widget process alive across rebuilds; stop it so the new build is loaded.
subprocess.run(["pkill", "-f", str(plugins / "CareLinkWidget.appex" / "Contents" / "MacOS" / "CareLinkWidget")],
               check=False)
if app_group:
    # Register the new extension right away so pluginkit/chronod drop the cached version of the
    # previous build (it otherwise kept reporting an old version for the same path).
    subprocess.run(["pluginkit", "-a", str(plugins / "CareLinkWidget.appex")], check=False)
print(app)

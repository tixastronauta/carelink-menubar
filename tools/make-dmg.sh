#!/bin/sh
# Packages build/CareLink Menubar.app into a drag-to-install disk image.
# Usage: tools/make-dmg.sh [output.dmg]   (default: build/CareLink-Menubar.dmg)
# The file name has no version on purpose, so the "latest release" download link never changes.
set -eu
cd "$(dirname "$0")/.."
app="build/CareLink Menubar.app"
out="${1:-build/CareLink-Menubar.dmg}"
[ -d "$app" ] || { echo "Build the app first: python3 tools/build-menubar.py" >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
cat > "$staging/First launch.txt" <<'EOF'
CareLink Menubar - first launch

1. Drag "CareLink Menubar" onto the Applications folder.
2. Open it from Applications. macOS will say it cannot verify the app, because this free,
   open-source build is not notarized by Apple. Click "Done".
3. Open System Settings > Privacy & Security, scroll down and click "Open Anyway" next to
   CareLink Menubar, then confirm. You only need to do this once per version.

The app then appears in the menu bar. Unofficial and read-only: it never controls your pump.
More help: https://github.com/tixastronauta/carelink-menubar
EOF

rm -f "$out"
hdiutil create -volname "CareLink Menubar $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$out" >/dev/null
shasum -a 256 "$out" | sed "s|  .*/|  |" > "$out.sha256"
echo "$out ($version)"

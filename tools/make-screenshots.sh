#!/bin/sh
# Regenerates assets/screenshots/*.png from synthetic data (see tools/make-screenshots.swift).
set -eu
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
# The widget extension has its own @main; strip it so the renderer can reuse its views.
sed '/^@main/,$d' macos/WidgetExtension.swift > "$scratch/WidgetViews.swift"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path build/module-cache \
  macos/AppVariant.swift macos/Localization.swift macos/Model.swift macos/NativeCore.swift macos/Diagnostics.swift \
  macos/CredentialVault.swift macos/NativeAPI.swift macos/WebLogin.swift macos/LaunchAtLogin.swift \
  macos/Store.swift macos/Preferences.swift macos/PopoverView.swift macos/WidgetShared.swift \
  "$scratch/WidgetViews.swift" tools/make-screenshots.swift -o "$scratch/make-screenshots"
mkdir -p assets/screenshots
"$scratch/make-screenshots" assets/screenshots

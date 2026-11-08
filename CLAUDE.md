# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

The rules in AGENTS.md (read-only scope, secret handling, Portuguese (Portugal) for user
communication, required test runs) are mandatory. Keep both files consistent.

## What this is

CareLink Menubar: a native macOS 14+ menu bar app (Swift/SwiftUI, no Xcode project) showing
glucose, trend, active insulin and a history chart from the European Medtronic CareLink
cloud. Standalone since 0.2; current version 0.3.0 (set in `tools/build-menubar.py`). The Python package `carelink_proto/` is the earlier
prototype, preserved but no longer called by the app; `vendor/` (git-ignored) holds the
upstream AGPL client it was derived from.

## Commands

```sh
# Python prototype tests (required after any change)
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python -m unittest tests.test_prototype.<Class>.<test_name>   # single test

# Build the universal app -> build/CareLink Menubar.app
# Signs with a valid "Apple Development" identity (has a Team ID, so Keychain
# "Always Allow" survives rebuilds), else ad-hoc.
# CARELINK_SIGN_IDENTITY overrides. Without a Team ID each rebuild re-prompts once.
python3 tools/build-menubar.py

# Regenerate the app icon (assets/AppIcon.icns, committed; the build only copies it)
xcrun swiftc tools/make-icon.swift -o build/make-icon && build/make-icon assets

# Swift checks: standalone executables (each check file has its own @main)
S="xcrun swiftc -swift-version 5 -module-cache-path build/module-cache"
$S macos/Localization.swift macos/Model.swift macos/ModelChecks.swift -o build/model-checks && ./build/model-checks
$S macos/Localization.swift macos/Model.swift macos/NativeCore.swift macos/Diagnostics.swift macos/NativeChecks.swift -o build/native-checks && ./build/native-checks
$S macos/Localization.swift macos/Model.swift macos/NativeCore.swift macos/Diagnostics.swift macos/CredentialVault.swift macos/NativeAPI.swift \
   macos/WebLogin.swift macos/Store.swift macos/NativeIntegrationChecks.swift \
   -o build/native-integration-checks && ./build/native-integration-checks
$S macos/Localization.swift macos/Model.swift macos/WidgetShared.swift macos/WidgetChecks.swift -o build/widget-checks && ./build/widget-checks
$S macos/Localization.swift macos/Model.swift macos/NativeCore.swift macos/CredentialVault.swift macos/VaultChecks.swift \
   -o build/vault-checks && ./build/vault-checks   # touches the real Keychain with a synthetic, unique service
```

In zsh, `$S` will not word-split; write the `xcrun swiftc ...` command out in full.
Checks use `precondition` and print a single `PASS:` line. Run them before
rebuilding the app. They are build/model tests, not live UI validation; keep that
distinction in the docs. `NativeLiveCheck.swift` is a developer-only real read check
using a borrowed in-memory token. Do not run it routinely or enable renewal in it.

## Language

The app is Portuguese (pt-PT) and English, switchable at runtime (Settings → General).
`Localization.swift` holds `tr()`: Portuguese source strings are the keys, English lives in
`L10n.english`; longer help texts use `info.*` identifiers with both languages. Every new
user-facing string must go through `tr()` and get an English entry; numbers and dates use
`L10n.locale`. Run `python3 tools/check-translations.py` after adding text. Checks set
`L10n.choice = .portuguese` before asserting Portuguese strings.

## Architecture (`macos/`)

The app sources compiled by `tools/build-menubar.py` are listed explicitly in that
script (`*Checks.swift` and `NativeLiveCheck.swift` are excluded). Add new app files there.

- `NativeCore.swift`: pure logic shared by the app and the checks. `Endpoints` (fixed
  EU URLs), `NetworkPolicy.allows` (allowlist of GET endpoints and the only two
  permitted POST bodies: display/message and OAuth token), `Tokens`, OAuth/PKCE helpers
  (`OAuthFlow`), and `NativeParser`, which normalizes the raw `patientData` JSON into a
  `Snapshot`.
- `Diagnostics.swift`: opt-in developer logging (see AGENTS.md) and `shape()`, which lists
  payload field paths/types without values. `NativeAPI.request` records every response
  through it; keep redaction of tokens/codes intact.
- `NativeAPI.swift`: URLSession client with redirects disabled. Every request passes
  through `NetworkPolicy`, it refreshes and rotates tokens, and it persists them via
  `TokenStorage`.
- `CredentialVault.swift`: `TokenStorage` protocol and the Keychain implementation
  (the only token store). Checks inject in-memory vaults.
- `WebLogin.swift`: `ASWebAuthenticationSession` (ephemeral) login on the official page.
- `Store.swift`: `@MainActor CareLinkStore`, the app's state, 10-minute refresh timer,
  wake handling, and login/logout. A `generation` counter lets logout cancel
  in-flight work so stale results are dropped. Preserve those checks.
- `Model.swift`: `Snapshot`/`Reading`/`ChartPoint` view models and `RefreshGate`.
- `App.swift` / `PopoverView.swift`: NSStatusItem, popover and SwiftUI chart.
- `Notifications.swift`: `Notifier` (UserNotifications) for technical alerts only; the
  once-per-episode logic is `TechnicalAlerts` in `Model.swift`, fed from `CareLinkStore.tick`.
- `SettingsView.swift` / `LaunchAtLogin.swift` / `Preferences.swift`: settings window
  as toolbar tabs (`SettingsTabController`, one SwiftUI `Pane` per tab; the window resizes
  per tab). Display toggles live in `Preferences` and are read by `PopoverView`/`App`.
  Opened from the panel's gear button. Preferences live in UserDefaults and
  must never hold health data. `GlucoseRange` and `RefreshGate` in `Model.swift` hold
  the testable logic.

Widget (`WidgetExtension.swift`, built into `Contents/PlugIns/CareLinkWidget.appex` by the build
script; needs a Team ID, skipped when ad-hoc). The app writes `WidgetSummary` (`WidgetShared.swift`)
to the App Group container and calls `WidgetCenter.reloadAllTimelines()`; the widget only reads it
(no tokens, no network). Hard-won rules:
- Link the extension with `-e _NSExtensionMain`; the Swift `@main` entry crashes in ExtensionFoundation.
- The App Group must be prefixed with the signature's real Team ID. The ID in parentheses in an
  "Apple Development: Name (ID)" certificate name is personal, not the Team ID; the build reads
  `TeamIdentifier` from a scratch signature. A wrong prefix makes containermanagerd reject the app.
- Do not use `.atomic` writes in the group container (staged outside, denied); write a temp file
  inside it and `rename(2)`.
- macOS keeps the old widget process across rebuilds; the build `pkill`s it.
- `EnvironmentValues.widgetFamily` is read-only; render `SummaryContent(entry:layout:)` (small,
  medium, large) for previews; `containerBackground` only renders inside WidgetKit, so compose
  `backgroundChart` behind it by hand.
- The widget clicks to `carelinkmenu://open` (URL scheme in the app's Info.plist) → panel.

Performance: the panel redraws often (5 s tick, every toggle). Never allocate formatters per
reading (`Snapshot.parseDate` uses static ones; `Reading.date` is parsed once), and only
re-measure the panel when `AppDelegate.layoutSignature` changes.

With `NSHostingController.sizingOptions = []` the hosted view's `fittingSize` is 0; measure with
`sizeThatFits(in:)` and set `preferredContentSize` (the settings tabs resize from it).

Plain `swiftc` has no SwiftUI macro plugin: `@State` and other macro-based wrappers fail
to compile. Use `@ObservedObject`, closures to the AppKit delegate, or AppKit (`NSAlert`).

Health data may be written to disk only after first-launch consent (`Consent.swift`; nothing
reads CareLink before it). Withdrawing consent (Settings → About) signs out, deletes the app's
files and quits; any new on-disk store must be deleted there too. The build also packs
`Source.tar.gz`, LICENSE and NOTICE into the bundle for AGPL compliance.

## Docs

All documentation and code comments are in English (the Portuguese UI strings in
`Localization.swift` are translations, not docs). `README.md` is the public overview with
screenshots from `tools/make-screenshots.sh` (synthetic data only). `docs/GUIDE.md` is the user
and developer guide, including the CareLink fields table and validation status: update it with
every change. `docs/HISTORY.md` summarises the prototype, 0.1, 0.2 and 0.3.

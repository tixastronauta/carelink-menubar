# CareLink Menubar guide

User and developer reference for CareLink Menubar 0.3. For a quick overview see the
[README](../README.md); for how the project got here see [HISTORY.md](HISTORY.md).

## Contents

- [First run](#first-run)
- [Using the app](#using-the-app)
- [Settings](#settings)
- [Desktop widget](#desktop-widget)
- [Notifications](#notifications)
- [Data, privacy and consent](#data-privacy-and-consent)
- [CareLink fields used](#carelink-fields-used)
- [Validation status and known limitations](#validation-status-and-known-limitations)
- [Development](#development)
- [Distribution](#distribution)
- [Releases and website](#releases-and-website)

## First run

1. Build and open `build/CareLink Menubar.app` (see the README). It can be moved to Applications.
2. Read and accept the consent window. Nothing is read from CareLink before you accept; **Quit**
   closes the app. The text can be read in Portuguese or English.
3. Click **Sign in to CareLink** and authenticate on the official European CareLink page, shown in
   a system web sheet (`ASWebAuthenticationSession`, ephemeral session, PKCE). Never enter your
   credentials anywhere else.
4. The app stores the OAuth tokens in your login Keychain and starts reading data.

## Using the app

### Menu bar

- **Left click:** opens or closes the panel.
- **Right click:** shows **Open**, **Settings…** and **Quit**.
- **The item itself:** shows the glucose value, the trend arrow (optional) and a 3-hour sparkline
  (optional).
  - The value turns orange outside the target range and red below 54 mg/dL. It is not coloured
    while the reading is old or after an error.
  - A trailing "!" marks old data or a failed refresh.
- **Hover:** a tooltip shows the unit and the reading age.

### Panel

- **Header:**
  - **Camera:** copies an image of the panel to the clipboard. The image has no header buttons, an
    opaque background, the current appearance and the screen's scale. The panel flashes briefly and
    the macOS screen-capture sound plays.
  - **Refresh:** refreshes now.
  - **Gear:** opens Settings.
- **Value block:** glucose, trend arrow and unit. Next to it: active insulin, SmartGuard state,
  sensor reading age ("3min ago"), last update and next update ("in 9min"). Hovering an age shows
  the exact time.
- **Time in range card:**
  - CareLink's 24-hour time in range, always for 70–180 mg/dL. It does not use your target range.
  - Green from 70%, the common guideline goal, orange below that.
  - A bar with the below/in/above split.
  - Optional average, coefficient of variation (standard deviation on hover) and GMI.
- **Consumables card:**
  - **Reservoir:** units and fill %.
  - **Battery:** the icon shows a bolt while charging.
  - **Infusion set:** time left, or "Change".
  - **Sensor:** time left.
  - Sensor time turns orange under 24h and red under 6h; infusion set time under 12h and 2h.
- **Warnings** (shown only when relevant):
  - pump suspended;
  - sensor messages (warm-up, calibration…);
  - phone or pump connection, only while the reading is old;
  - sensor or infusion set ending (red level);
  - old reading ("Last reading 17min ago"), missing reading time, or time ahead of the Mac's clock;
  - CareLink errors.
- **Chart:**
  - 6h, 12h or 24h, with the target band and dots for out-of-range readings.
  - Bolus (filled drop), SmartGuard auto correction (small drop) and meal (fork and knife) markers.
    Hovering a marker shows the amount and time.
- **Diagnostics badge:** an orange "Diagnostics" label in the header while diagnostic mode is on.

### Refreshing

- **Interval:** every 5 or 10 minutes while the app runs and the Mac is awake, with an immediate
  refresh after wake when one is due.
- **Old readings:** when the reading is 15–30 minutes old, the app refreshes early, at most once
  every 2 minutes.
- **Failures:** after a failed fetch it retries in about a minute.

## Settings

Settings opens next to the panel and keeps the panel open, so changes can be previewed live.
Less obvious options have an ⓘ button: hover for a tooltip, click for the full text.

| Tab | Options |
| --- | ------- |
| **General** | Language: Automatic (macOS), Português or English, applied immediately. Open at Mac login (`SMAppService`; the panel stays closed on login launches). Refresh every 5 or 10 min. Widget: show data in the desktop widget. Notifications: technical problems. |
| **Display** | Colour outside the target range, trend arrow and sparkline in the menu bar. Panel elements: time in range, average/CV/GMI, SmartGuard, consumables, sensor messages, connection messages. Old-reading and CareLink errors are always shown. |
| **Chart** | Target range: manual limits (50–120 and 120–300 mg/dL, default 70–180), or the pump's alert limits (`limits[0]`). Band, out-of-range dots, boluses and meals, SmartGuard auto corrections. |
| **Account** | Status card (connected with the account e-mail or user name, expired, signed out, signing in), last update, Sign In / Sign Out (with confirmation). |
| **Advanced** | Diagnostic mode, Open Logs Folder, Delete Logs, Copy Payload Structure. |
| **About** | Version, license, source code on GitHub, original project, consent date and **Withdraw Consent…**. |

## Desktop widget

Add it from the desktop: right-click → **Edit Widgets…** → search "CareLink". It is also available
in Notification Center.

- **Small:** value with range colour, trend, unit and reading age, with the real last-3-hour trace
  drawn faintly behind it.
- **Medium:** the same style, wider, with the 24-hour time in range on the right.
- **Large:**
  - value and active insulin;
  - 3-hour chart with the target band and hours;
  - time in range bar;
  - consumables, with the same ending colours as the panel.
- **Behaviour:**
  - The reading age updates every minute.
  - After 15 minutes the value turns grey and the age orange.
  - Text follows the app's language.
  - Clicking the widget opens the panel (`carelinkmenu://open`).
- **Data:** the app writes `widget-summary.json`, mode 600, to
  `~/Library/Group Containers/<TeamID>.local.tcx.carelink.menu/`, after consent.
  - Contents: value, trend, time, unit, last 3 hours, target, time in range, active insulin,
    consumables and language. Never tokens.
  - It is replaced on every refresh and deleted on sign-out, on consent withdrawal or when widget
    sharing is turned off.
  - The widget only reads this file: it has no tokens and never contacts CareLink.
- **Signing:** requires a Team ID (Apple Development or Developer ID). Ad-hoc builds do not
  include the widget.

## Notifications

Technical notifications only, never glucose values or glucose alarms. They can be turned off in
Settings → General. Clicking one opens the panel.

| Notification | When |
| --- | --- |
| Session expired | Once per episode |
| No new readings | Reading older than 30 min, only right after a successful fetch, to avoid false alarms after sleep |
| Sensor ending | When entering the under-24h and the under-6h levels |
| Infusion set ending | When entering the under-12h and the under-2h levels |

The last notified sensor and infusion set levels persist, so relaunching does not repeat them.
They re-arm after a change.

## Data, privacy and consent

- **Network:** only MiniMed's European CareLink endpoints are used. `NetworkPolicy` allows a few
  GET endpoints and exactly two POST bodies: `display/message` (reads data) and the OAuth token
  request (sign-in and refresh). Redirects are refused.
- **Tokens:** stored in the login Keychain only (`CredentialVault`), never synchronised with iCloud,
  never logged.
- **Consent:** the first launch shows a blocking consent window. It shows again whenever
  `Consent.version` increases. It explains that:
  - health data is read by automated systems;
  - it may be stored in files on this Mac;
  - it is not actively shared with any entity;
  - protecting the Mac and the data is the user's responsibility;
  - the app is unofficial and does not replace the pump, sensor, MiniMed app or their alarms.
- **Files written after consent:**
  - the widget summary (see above);
  - diagnostic logs (below).
- **Withdraw Consent** (Settings → About) signs out, turns diagnostics off, deletes those files and
  quits.
- **Preferences:** stored in UserDefaults. They contain no health data apart from the last notified
  consumable levels (0–2).
- **Clipboard:** the panel image contains health data and only leaves the Mac if you paste it
  somewhere.

### Diagnostic mode

Off by default. Turn it on in Settings → Advanced; it stays on until you turn it off.

- **What it writes:** every CareLink request and response, as one JSON line per request, in
  `~/Library/Logs/CareLink Menubar/`. The folder is mode 700 and the files 600, one `.jsonl` per day.
- **What it hides:** tokens, OAuth codes, secrets and JWT-like values are always redacted, including
  camelCase keys.
- **Clean-up:** files older than 7 days are deleted at launch, when the mode is turned on and once
  a day while writing.
- **Copy Payload Structure:** copies only field names and types from the last reading, never
  values. Useful for sharing what CareLink sends without sharing health data.

## CareLink fields used

All values come from `patientData` in the `display/message` response.

| Field | Used for | Status |
| ----- | -------- | ------ |
| `lastSG`, `sgs[]`, `clientTimeZoneName`, `bgUnits` | Value, history, time zone, unit | Confirmed on a real Flex payload (local times converted with the IANA zone, ambiguous DST times rejected) |
| `lastSGTrend` | Trend arrow | Confirmed: `UP_DOUBLE`, `UP`, `DOWN`, `NONE` seen. `DOUBLE_UP` style also accepted |
| `activeInsulin.amount` | Active insulin | Confirmed |
| `timeInRange`, `belowHypoLimit`, `aboveHyperLimit` | Time in range card | Confirmed: match 70–180 mg/dL and add up to 100 |
| `therapyAlgorithmState.autoModeShieldState`, `safeBasalDuration` | SmartGuard | `AUTO_BASAL` confirmed; other codes shown as received |
| `reservoirRemainingUnits`, `reservoirLevelPercent` | Reservoir | Confirmed (`-1` right after a change is ignored) |
| `pumpBatteryLevelPercent`, `isPumpCharging`, `pumpSuspended` | Pump status | Confirmed |
| `infusionStatus`, `infusionRemainingDuration` | Infusion set | Confirmed: `END_OF_LIFE` when due; duration in **minutes** (4319 right after a 3-day set change) |
| `sensorDurationHours` | Sensor time left | Confirmed |
| `sensorState`, `systemStatusMessage` | Sensor messages | Only `NO_ERROR_MESSAGE` seen; other codes from third-party notes |
| `conduitInRange`, `conduitMedicalDeviceInRange` | Connection messages | Interpretation unconfirmed. `conduitSensorInRange` is ignored: it is false on a Flex with fresh data |
| `limits[0].lowLimit/highLimit` | Optional target range | Confirmed as alert limits (70–200), not a therapy target |
| `markers[]` (`INSULIN`, `MEAL`) | Chart markers | Confirmed. `AUTO_BASAL_DELIVERY` (about 180 a day) is not drawn |

For mmol/L accounts, `sg` and limit values above 35 are treated as mg/dL and converted, as
third-party clients assume. No real mmol/L payload has been seen.

Fields such as names, serial numbers and device identifiers are never displayed or stored outside
diagnostic logs.

## Validation status and known limitations

**Validated on the development Mac, with a European account and a MiniMed Flex:**

- sign-in with the native flow;
- session persistence across relaunches;
- reading and display of all confirmed fields above;
- launch-at-login registration;
- desktop widget in all three sizes;
- the user interface in both languages.

**Not verified:**

- other pumps and regions;
- mmol/L accounts;
- MFA;
- care-partner accounts;
- running on an Intel Mac (the universal build compiles).

**Synthetic checks** (`macos/*Checks.swift`) cover:

- parsing, DST and units;
- PKCE and OAuth callback validation;
- the network allowlist and token rotation;
- cancellation and logout races;
- refresh scheduling and alert transitions;
- diagnostics redaction;
- the widget hand-off;
- both languages.

These are build and model tests, not live UI validation.

**Known limitation:** if a fetch exceeds 120 s after the server has already rotated the refresh
token, the timeout cancellation discards the new token, and a new sign-in may be needed. Fixing this
requires telling timeout cancellation apart from logout cancellation. Logout must keep dropping
tokens.

## Development

```sh
# Build -> build/CareLink Menubar.app (universal, signed)
python3 tools/build-menubar.py

# Synthetic checks (see CLAUDE.md for the full commands)
xcrun swiftc -swift-version 5 -module-cache-path build/module-cache \
  macos/Localization.swift macos/Model.swift macos/ModelChecks.swift -o build/model-checks && ./build/model-checks

# Translation coverage, README screenshots, app icon
python3 tools/check-translations.py
./tools/make-screenshots.sh
xcrun swiftc tools/make-icon.swift -o build/make-icon && build/make-icon assets

# Python prototype tests
.venv/bin/python -m unittest discover -s tests -v
```

### Code and build notes

- **No Xcode project:** `tools/build-menubar.py` compiles the app sources listed in the script with
  `swiftc` for arm64 and x86_64, then joins them with `lipo`.
- **Widget extension:** compiled separately and linked with `-e _NSExtensionMain` (the Swift `@main`
  entry crashes in ExtensionFoundation). It gets a unique build number per build, because the widget
  gallery caches its sizes per version. The build stops the stale widget process afterwards.
- **App Group:** prefixed with the signature's real Team ID, read from a scratch signature. The ID
  in an "Apple Development: Name (ID)" certificate name is a personal ID, not the Team ID. Writes to
  the group container use a temp file and `rename(2)`, because `.atomic` writes are refused there.
- **Signing:** Apple Development is preferred: with a Team ID, Keychain "Always Allow" survives
  rebuilds. The identity needs the Apple WWDR G3 intermediate certificate in the Keychain. Ad-hoc
  builds prompt once per rebuild and skip the widget.
- **SwiftUI without macros:** plain `swiftc` has no SwiftUI macro plugin, so `@State` cannot be
  used. Views rely on `@ObservedObject` and AppKit.
- **Localization:** all user-facing text goes through `tr()` in `Localization.swift`. Portuguese
  source strings are the keys and English lives in a table. Run `tools/check-translations.py` after
  adding text.
- **Panel arrow:** the panel is an `NSPopover` with the system `menu` material. Its arrow cannot be
  tinted, so it is hidden with the undocumented `shouldHideAnchor` key, only when supported.
- **Icon:** `assets/AppIcon.icns` is original artwork drawn by `tools/make-icon.swift`, with no
  MiniMed branding.

## Distribution

- **Current builds:** signed with Apple Development (or ad-hoc). They are meant for the developer's
  own Mac and show Gatekeeper warnings elsewhere.
- **Sharing builds:** needs a Developer ID certificate (paid Apple Developer membership) and
  notarization. The App Store is not needed. Do not disable Gatekeeper to work around this.
- **AGPL-3.0:** keep the source available and the attributions intact when redistributing. Each
  bundle includes `LICENSE`, `NOTICE.txt` and `Source.tar.gz`.

## Releases and website

### Publishing a release

1. Update the version in `tools/build-menubar.py` (`CFBundleShortVersionString` and
   `CFBundleVersion`) and the notes in `.github/release-notes.md` if needed.
2. Commit, then tag and push: `git tag -a v0.3.1 -m "CareLink Menubar 0.3.1" && git push origin v0.3.1`.
3. `.github/workflows/release.yml` then runs on a macOS runner:
   - builds the app;
   - packages `CareLink-Menubar.dmg` and its SHA-256;
   - creates the GitHub release with the install notes.
4. The asset always has the same name, so `https://github.com/tixastronauta/carelink-menubar/releases/latest/download/CareLink-Menubar.dmg` always points to the newest version.

Running the workflow manually ("Run workflow") builds the DMG as a downloadable artifact without
publishing a release, which is useful for testing.

**Signing in CI:**
- Without secrets, the build is ad-hoc signed and the desktop widget is left out.
- To include the widget, export an Apple Development (or Developer ID) certificate with its private
  key as `.p12`, then add it as the repository secrets `SIGNING_CERT_P12` (base64) and
  `SIGNING_CERT_PASSWORD`.
- This has not been tested yet. A widget signed this way on other Macs is also unverified.
- Builds are never notarized without a paid Apple Developer membership. Users approve the first
  launch in System Settings → Privacy & Security → **Open Anyway**.

To build a DMG locally: `python3 tools/build-menubar.py && ./tools/make-dmg.sh`.

### Website

`site/index.html` is a self-contained landing page for end users, with download, features, privacy,
install steps and FAQ. `.github/workflows/pages.yml` publishes it to `https://tixastronauta.github.io/carelink-menubar/` whenever `site/` or
`assets/` change on `main`. The workflow copies the icon and screenshots from `assets/`.

- **One-time setup:** repository Settings → Pages → Source: **GitHub Actions**.
- **Plan limitation:** GitHub Pages needs a paid plan while the repository is private; it is free
  once the repository is public.
- **Local preview:** copy `site/` together with `assets/AppIcon-1024.png` and `assets/screenshots`
  into one folder and open `index.html`.

# CareLink Menubar guide

User and developer reference for CareLink Menubar 0.3. For a quick overview see the
[README](../README.md); for how the project got here see [HISTORY.md](HISTORY.md).

## Contents

- [First run](#first-run)
- [Using the app](#using-the-app)
- [Settings](#settings)
- [Desktop widget](#desktop-widget)
- [Notifications](#notifications)
- [In-app updates](#in-app-updates)
- [Data, privacy and consent](#data-privacy-and-consent)
- [CareLink fields used](#carelink-fields-used)
- [Validation status and known limitations](#validation-status-and-known-limitations)
- [Development](#development)
- [Distribution](#distribution)
- [Releases and website](#releases-and-website)

## First run

1. Install `CareLink Menubar` from the DMG into Applications, or build and open the development
   variant `build/CareLink Menubar Dev.app` (see [Development](#development)).
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
| **General** | Language: Automatic (macOS), Português or English, applied immediately. Open at Mac login (`SMAppService`; the panel stays closed on login launches). Refresh every 5 or 10 min. Widget: show data in the desktop widget. Notifications: technical problems and new versions. |
| **Display** | Colour outside the target range, trend arrow and sparkline in the menu bar. Panel elements: time in range, average/CV/GMI, SmartGuard, consumables, sensor messages, connection messages. Old-reading and CareLink errors are always shown. |
| **Chart** | Target range: manual limits (50–120 and 120–300 mg/dL, default 70–180), or the pump's alert limits (`limits[0]`). Band, out-of-range dots, boluses and meals, SmartGuard auto corrections. |
| **Account** | Status card (connected with the account e-mail or user name, expired, signed out, signing in), last update, Sign In / Sign Out (with confirmation). |
| **Advanced** | Diagnostic mode, Open Logs Folder, Delete Logs, Copy Payload Structure. |
| **About** | Version, updates (check automatically, on by default; last check; **Check Now**), license, source code on GitHub, original project, consent date and **Withdraw Consent…**. |

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
  - Timeline: WidgetKit renders every timeline entry ahead of time, and the app replaces the
    timeline on each new reading. So the widget asks for few entries: one per minute (aligned to
    the reading) until the reading turns stale, at most 10; once stale, one every 5 minutes for an
    hour; with no data, a single entry. Each timeline names its own reload date. Until 0.3.1 it
    asked for 60 per-minute entries, most of them rendered and discarded on the next reading,
    which showed up as short CPU spikes of the widget process.
  - The small and medium background trace is a plain SwiftUI path, cheaper than Swift Charts; the
    large widget keeps the chart.
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

Technical notifications and new-version notices only, never glucose values or glucose alarms. They can be turned off in
Settings → General. Clicking one opens the panel.

| Notification | When |
| --- | --- |
| Session expired | Once per episode |
| No new readings | Reading older than 30 min, only right after a successful fetch, to avoid false alarms after sleep |
| Sensor ending | When entering the under-24h and the under-6h levels |
| Infusion set ending | When entering the under-12h and the under-2h levels |
| New version available | Once per version found by a scheduled update check; clicking it opens the update window |

The last notified sensor and infusion set levels persist, so relaunching does not repeat them.
They re-arm after a change.

## In-app updates

Release builds update themselves with [Sparkle](https://sparkle-project.org) 2. From 0.3.3 on;
earlier versions have to install 0.3.3 from the DMG once.

- **Checks:** once a day, on by default (Settings → About → Updates, where **Check Now** is too).
  A check only downloads `appcast.xml`, the newest release's feed, from GitHub Releases. It sends
  no health data, account details or system profile (`SUEnableSystemProfiling` off), and it starts
  only after consent.
- **Notice, not interruption:** a scheduled check never opens a window by itself (Sparkle's gentle
  reminders). A new version shows a notice at the top of the panel and, if notifications are on, a
  notification. Either opens Sparkle's window with the release notes and **Skip This Version**,
  **Remind Me Later** and **Install Update**; installing replaces the app and relaunches it.
- **Integrity:** the update archive and the feed itself are signed with an EdDSA key. The app
  carries the public key (`SUPublicEDKey`), requires a signed feed (`SURequireSignedFeed`) and
  verifies the archive before extracting it. Sparkle also checks that the new app's code signature
  is valid.
- **Language:** Sparkle's windows use its own translations (European Portuguese included). The app
  sets its language for them at launch, so after changing the language in Settings they follow
  from the next launch.
- **Development builds** never check for or install updates (see [Development](#development)).

## Data, privacy and consent

- **Network:** only MiniMed's European CareLink endpoints are used. `NetworkPolicy` allows a few
  GET endpoints and exactly two POST bodies: `display/message` (reads data) and the OAuth token
  request (sign-in and refresh). The `display/message` body may hold only `username`, `role`,
  `patientId` and, for care-partner reads, the fixed client declaration `appVersion` "3.8" and
  `os` "android": since October 2026 CareLink answers care-partner reads without it with HTTP 206
  "Upgrade application" (shown as an "update the app" error). Patient reads do not send it.
  Redirects are refused. Separately, release builds fetch the
  update feed and archives from GitHub (see [In-app updates](#in-app-updates)); that traffic
  carries no health data.
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
  `~/Library/Logs/CareLink Menubar/` (`CareLink Menubar Dev/` for the development build). The folder
  is mode 700 and the files 600, one `.jsonl` per day; a day over 10 MB continues in
  `carelink-DAY-2.jsonl`, `-3`, and so on.
- **What it hides:** tokens, OAuth codes, secrets and JWT-like values are always redacted, including
  camelCase keys.
- **Clean-up:** files older than 7 days are deleted, and the folder is capped at 50 MB (the oldest
  files go first; the file being written is kept). This runs at launch, when the mode is turned on,
  once a day and whenever a new file starts. Each refresh logs roughly 20 KB, so a 1-minute
  refresh writes about 30 MB a day. The release build also deletes logs left in
  `~/Library/Logs/CareLink Menu/`, the folder used before 0.3.0, at launch, with "Delete logs" and
  on consent withdrawal.
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
- a care-partner account linked to one patient (sign-in, read with the `appVersion`/`os`
  declaration, panel display), after the 206 "Upgrade application" fix;
- launch-at-login registration;
- desktop widget in all three sizes;
- the user interface in both languages.

**Not verified:**

- other pumps and regions;
- mmol/L accounts;
- MFA;
- running on an Intel Mac (the universal build compiles).

**Synthetic checks** (`macos/*Checks.swift`) cover:

- parsing, DST and units;
- PKCE and OAuth callback validation;
- the network allowlist and token rotation;
- the care-partner request body and the 206 "Upgrade application" error;
- cancellation and logout races;
- refresh scheduling and alert transitions;
- diagnostics redaction;
- the widget hand-off, timeline plan and background curve geometry;
- both languages.

These are build and model tests, not live UI validation.

**Known limitation:** if a fetch exceeds 120 s after the server has already rotated the refresh
token, the timeout cancellation discards the new token, and a new sign-in may be needed. Fixing this
requires telling timeout cancellation apart from logout cancellation. Logout must keep dropping
tokens.

## Development

```sh
# Development variant -> build/CareLink Menubar Dev.app (universal, signed)
python3 tools/build-menubar.py
# Release variant -> build/CareLink Menubar.app (what the release workflow builds)
python3 tools/build-menubar.py --release

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

### Development and release builds

The installed release and a development build run side by side. The build script makes a
**development variant** by default and the **release variant** only with `--release`:

| | Release | Development |
| --- | --- | --- |
| App | `CareLink Menubar` (`local.tcx.carelink.menu`) | `CareLink Menubar Dev` (`local.tcx.carelink.menu.dev`) |
| Icon and marks | standard | orange icon with a "DEV" band, "DEV" in the menu bar and panel |
| Preferences, consent | own UserDefaults domain | own UserDefaults domain |
| Keychain session | `local.tcx.carelink.menu.oauth.eu` | `local.tcx.carelink.menu.dev.oauth.eu` |
| App Group, widget | `<Team>.local.tcx.carelink.menu`, "CareLink" | `<Team>.local.tcx.carelink.menu.dev`, "CareLink Dev" |
| Widget URL, logs | `carelinkmenu://`, `~/Library/Logs/CareLink Menubar` | `carelinkmenu-dev://`, `~/Library/Logs/CareLink Menubar Dev` |
| Updates | Sparkle, daily | none |

`macos/AppVariant.swift` holds these identifiers; the build writes `CareLinkVariant` into both
Info.plists. Each variant signs in separately, so there are two CareLink sessions on the account;
they never share tokens (refresh tokens rotate, so sharing would sign one of them out). Whether
CareLink limits concurrent sessions is not verified yet.

Day to day: develop with the Dev build, merge, tag; the installed release then updates itself like
anyone else's.

**Testing an update locally** (development variant, nothing published): build an "old" and a "new"
version with `CARELINK_VERSION=<x.y.z>` and `CARELINK_TEST_FEED_URL=http://127.0.0.1:<port>/appcast.xml`,
zip the new one, sign it and the feed with `build/deps/Sparkle-*/bin/sign_update --account
carelink-menubar`, generate the feed with `tools/appcast.py`, serve the folder with
`python3 -m http.server`, and run the old build.

### Code and build notes

- **No Xcode project:** `tools/build-menubar.py` compiles the app sources listed in the script with
  `swiftc` for arm64 and x86_64, then joins them with `lipo`.
- **Widget extension:** compiled separately and linked with `-e _NSExtensionMain` (the Swift `@main`
  entry crashes in ExtensionFoundation). It gets a unique build number per build, because the widget
  gallery caches its sizes per version. The build stops the stale widget process afterwards
  and registers the new extension with `pluginkit -a`, so the system does not keep reporting the
  previous build's version. Running the app from `build/` works, but `/Applications` gives the
  extension a stable registration.
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
  MiniMed branding. `build/make-icon assets dev` draws the development icon (`AppIcon-Dev.icns`).
- **Sparkle:** the build downloads Sparkle's release archive once into `build/deps`, checks it
  against the SHA-256 pinned in `tools/build-menubar.py`, links `Sparkle.framework` with an
  `@executable_path/../Frameworks` rpath and signs its helpers inside-out (never `--deep`).
  `CFBundleVersion` is derived from the version (0.3.3 → 303) because Sparkle compares it.
  `tools/appcast.py` (tested in `tests/test_appcast.py`) writes the feed. Sparkle's licence (MIT) is
  bundled as `Sparkle-LICENSE.txt` and named in `NOTICE.txt`.

## Distribution

- **Current builds:** signed with Apple Development (or ad-hoc). They are meant for the developer's
  own Mac and show Gatekeeper warnings elsewhere.
- **Sharing builds:** needs a Developer ID certificate (paid Apple Developer membership) and
  notarization. The App Store is not needed. Do not disable Gatekeeper to work around this.
- **AGPL-3.0:** keep the source available and the attributions intact when redistributing. Each
  bundle includes `LICENSE`, `NOTICE.txt` and `Source.tar.gz`.

## Releases and website

### Publishing a release

1. Update `VERSION` in `tools/build-menubar.py` (the build number follows from it) and add a
   `## <version>` section to `docs/HISTORY.md`: it becomes the update notes shown in the app.
   Update `.github/release-notes.md` if needed.
2. Commit, then tag and push: `git tag -a v0.3.3 -m "CareLink Menubar 0.3.3" && git push origin v0.3.3`.
3. `.github/workflows/release.yml` then runs on a macOS runner:
   - builds the release variant;
   - packages `CareLink-Menubar.dmg` and its SHA-256;
   - zips the app as `CareLink-Menubar.zip`, signs it with the `SPARKLE_ED_PRIVATE_KEY` secret,
     writes `appcast.xml` with `tools/appcast.py`, signs the feed and verifies it (the run fails
     if the secret is missing or the tag does not match the app version);
   - creates the GitHub release with the install notes and all four files.
4. The assets always have the same names, so `https://github.com/tixastronauta/carelink-menubar/releases/latest/download/CareLink-Menubar.dmg`
   always points to the newest version, and installed apps read `…/latest/download/appcast.xml`.

**Update signing key:** an EdDSA key pair made with Sparkle's `generate_keys --account
carelink-menubar`. The private key lives in the maintainer's login Keychain and in the
`SPARKLE_ED_PRIVATE_KEY` repository secret, with an offline backup (1Password); it must never be
committed. The workflow derives the public key from the secret (`tools/sparkle-public-key.swift`)
and stops if it differs from the app's `SUPublicEDKey`.
The public key is `SPARKLE_PUBLIC_KEY` in `tools/build-menubar.py`. Losing the private key, or
changing the public key, means installed apps can no longer update themselves.

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

To build a DMG locally: `python3 tools/build-menubar.py --release && ./tools/make-dmg.sh`.

### Website

`site/index.html` is a self-contained landing page for end users, with download, features, privacy,
install steps and FAQ. `.github/workflows/pages.yml` publishes it to `https://tixastronauta.github.io/carelink-menubar/` whenever `site/` or
`assets/` change on `main`. The workflow copies the icon and screenshots from `assets/`.

- **One-time setup:** repository Settings → Pages → Source: **GitHub Actions**.
- **Plan limitation:** GitHub Pages needs a paid plan while the repository is private; it is free
  once the repository is public.
- **Local preview:** copy `site/` together with `assets/AppIcon-1024.png` and `assets/screenshots`
  into one folder and open `index.html`.

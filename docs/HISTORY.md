# Project history

A short record of how CareLink Menubar evolved. The current behaviour is described in
[GUIDE.md](GUIDE.md).

## Python prototype (October 2026)

The first goal was to read glucose from a European CareLink account safely.

- **Starting point:** [ondrej1024/carelink-python-client](https://github.com/ondrej1024/carelink-python-client)
  (AGPL-3.0, commit `29051ca`), which documents support for the 780G but not the Flex.
- **Discovery:** public GET requests to the CareLink discovery and Auth0 configuration endpoints
  confirmed that Portugal maps to the `EU` region and that sign-in uses Auth0. No authenticated
  endpoint was called before the user signed in themselves.
- **Upstream audit:** the upstream client only GETs configuration, user and patient data, and POSTs
  `display/message` (a read) and OAuth refresh. It sends no pump commands. Its login printed tokens
  and `curl` commands with secrets in some errors, so the prototype replaced it with a local Auth0
  flow.
- **The `carelink_proto` wrapper:**
  - restricts exact URLs, methods and POST bodies;
  - refuses redirects;
  - uses timeouts;
  - stores tokens with private file permissions outside the repository.
- **First real read:** it showed that Flex timestamps arrive as local times without an offset,
  together with `clientTimeZoneName`. The parser was fixed to use the IANA zone and reject
  ambiguous DST times.

The prototype and its 20 tests remain in `carelink_proto/` and `tests/` for reference. The app no
longer uses them.

## 0.1: menu bar app on top of the prototype

A first SwiftUI menu bar app called the Python prototype as a subprocess, with a 120-second timeout
and SIGTERM/SIGKILL handling. It reused the prototype's token and depended on the project folder,
so it was not distributable.

## 0.2: standalone native app

Everything was rewritten in Swift, with no Python at runtime:

- **Sign-in:** native OAuth with PKCE through `ASWebAuthenticationSession`.
- **Tokens:** stored only in the Keychain.
- **Network:** a strict allowlist of requests.
- **Cancellation:** logout cancels in-flight work through a generation counter.
- **Health data:** kept in memory only.

Legacy tokens are never imported automatically.

## 0.3: everyday app

Built in close iteration with daily use. Highlights:

- **Settings:** a window with toolbar tabs, Portuguese/English localization switchable at runtime,
  and ⓘ explanations.
- **Panel:** time in range card with average, CV and GMI; consumables card; SmartGuard; sensor and
  connection messages; chart markers; out-of-range colouring; menu bar sparkline.
- **Notifications and launch:** technical notifications, including sensor and infusion set ending;
  launch at login.
- **Diagnostic mode:** with redaction. It was used to confirm the real payload fields (see the
  table in GUIDE.md).
- **Desktop widget:** three sizes, built without Xcode.
- **Consent:** first-launch consent replaced the "memory only" rule, so files such as the widget
  summary can exist.
- **Panel extras:** panel image copy, a denser panel material, and the popover arrow hidden.
- **Signing:** Apple Development signing, so Keychain approval survives rebuilds.
- **Code review:** an independent review led to eight fixes, for panel sizing, retry after failure,
  mmol/L plausibility, log retention, logout robustness and cache keys.
- **Name:** the app was renamed from "CareLink Menu" to **CareLink Menubar** before going public.
  Internal identifiers (`local.tcx.carelink.menu`, the Keychain service and the App Group) keep the
  old name, so existing installs keep their session, consent and widget.

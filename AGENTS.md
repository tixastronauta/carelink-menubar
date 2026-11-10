# CareLink experimental read-only prototype
Code, comments and all documentation: English. User communication: Portuguese (Portugal).
Never send pump commands, modify therapy, upload data, or add write endpoints.
POST /display/message retrieves data; OAuth POSTs only authenticate/refresh.
Do not run upstream CLI, proxy or login directly: they can expose secrets.
Never log credentials, tokens or authorization URLs. Raw responses and patient identity may
be written only by the opt-in Diagnostics mode (off by default, stays on until turned off with
a visible panel badge, private ~/Library/Logs/CareLink Menubar, 7-day retention, tokens always redacted). Never commit those
logs; agents read them only when the user asks.
Keep tokens and health data outside this repository, with private permissions.
Never commit real health data. Fixtures must be synthetic and explicitly labelled.
Flex: core read (glucose, trend, active insulin, history) validated on the developer's own Flex
account; device-status fields and other pumps remain unverified until a payload confirms them.
Run `.venv/bin/python -m unittest discover -s tests -v` after changes.
Preserve vendor source and AGPL attribution. No changes to other projects.

Native UI: `macos/`; build with `python3 tools/build-menubar.py`.
Run Swift model checks before rebuilding. Do not bundle tokens or health snapshots.
Keep `docs/GUIDE.md` current and distinguish build/model tests from live UI validation.

Native standalone app (0.2+): no Python subprocess or project path.
Health data on disk is allowed only after the first-launch consent (Consent.swift) is accepted:
never read CareLink before consent, keep files on this Mac only (private, never in the repo),
delete them on consent withdrawal, and bump Consent.version when the consent text changes materially.
Use ASWebAuthenticationSession for official-page login; never automate credentials.
Store tokens only in CredentialVault. Do not import legacy tokens automatically.
Logout cancels work before clearing Keychain/memory; preserve cancellation generation checks.
Test NativeChecks, NativeIntegrationChecks and WidgetChecks; VaultChecks uses a unique synthetic service.
README screenshots must come from synthetic data (tools/make-screenshots.sh), never real readings.
NativeLiveCheck is a developer-only read check; never enable renewal for a borrowed legacy token.
In-app updates (Sparkle) are release-only and fetch only the signed appcast and archives from GitHub
Releases: never send health data, tokens or a system profile with them. Never commit, print or log
the Sparkle EdDSA private key; never change SUPublicEDKey (installed apps would stop updating).
Develop with the default development build (separate identifiers); never point it at the release
Keychain service, App Group or update feed.

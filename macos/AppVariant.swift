import Foundation

/// Release or development build. The build script writes `CareLinkVariant` into the app's and the
/// widget's Info.plist; the development variant uses its own bundle ID (`local.tcx.carelink.menu.dev`),
/// so it runs beside the installed release with separate preferences, consent, Keychain session,
/// App Group, URL scheme and logs, and never updates itself.
/// A missing key (checks, older builds) means release, which keeps the original identifiers.
enum AppVariant: String {
    case release, dev

    static let current: AppVariant = {
        AppVariant(rawValue: Bundle.main.object(forInfoDictionaryKey: "CareLinkVariant") as? String ?? "") ?? .release
    }()

    var isDev: Bool { self == .dev }
    var displayName: String { isDev ? "CareLink Menubar Dev" : "CareLink Menubar" }
    /// Keychain service holding the OAuth tokens. The release value is unchanged since 0.2.
    var keychainService: String { isDev ? "local.tcx.carelink.menu.dev.oauth.eu" : "local.tcx.carelink.menu.oauth.eu" }
    /// URL scheme the widget opens to show the panel.
    var urlScheme: String { isDev ? "carelinkmenu-dev" : "carelinkmenu" }
    /// Folder under ~/Library/Logs for opt-in diagnostics.
    var logsFolder: String { displayName }
    /// Unified-log subsystem (status messages only, never values).
    var logSubsystem: String { isDev ? "local.tcx.carelink.menu.dev" : "local.tcx.carelink.menu" }
    /// Only the release checks for and installs updates; a development build must never be
    /// replaced by a published release.
    var updatesEnabled: Bool { !isDev }
}

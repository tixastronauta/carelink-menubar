import AppKit
import Sparkle

/// In-app updates with Sparkle (release variant only; see AppVariant.updatesEnabled).
/// Sparkle reads the appcast (SUFeedURL), downloads the update and installs it only if its EdDSA
/// signature matches SUPublicEDKey. Scheduled checks never open a window on their own ("gentle
/// reminders"): a found update shows a notice in the panel and, with notifications on, a macOS
/// notification; the user opens Sparkle's update window from either. Checks only fetch the
/// appcast from GitHub: no health data, tokens or system profile are sent.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Version waiting for the user's attention (panel notice); nil when none.
    @Published private(set) var pendingVersion: String? {
        didSet { if pendingVersion != oldValue { onPendingChange?(pendingVersion) } }
    }
    var onPendingChange: ((String?) -> Void)?
    /// Called once per scheduled discovery, to post a notification.
    var onFound: ((String) -> Void)?
    private var controller: SPUStandardUpdaterController?

    /// Release builds with a feed, or a local test build (CareLinkTestFeed).
    static var isEnabled: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let testFeed = info["CareLinkTestFeed"] as? Bool ?? false
        return info["SUFeedURL"] != nil && (AppVariant.current.updatesEnabled || testFeed)
    }

    var isAvailable: Bool { controller != nil }

    /// Starts Sparkle's scheduler (after consent; nothing to do in development builds).
    func start() {
        guard Self.isEnabled, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        objectWillChange.send()
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }
    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    /// Brings up Sparkle's window: the pending update, or a user-initiated check.
    func showUpdate() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate (always called on the main thread)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Scheduled updates are always shown by us (panel notice + notification), never as a
    /// window popping up over whatever the user is doing.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        // Sparkle shows its own window for user-initiated checks; only our reminders need state.
        guard !handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            self.pendingVersion = version
            if !userInitiated { self.onFound?(version) }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { self.pendingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { self.pendingVersion = nil }
    }
}

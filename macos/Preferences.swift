import Foundation

/// User display preferences in UserDefaults. No health data or credentials are stored here.
@MainActor
final class Preferences: ObservableObject {
    static let intervals: [Int] = [5, 10]
    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    @Published var lowLimit: Double { didSet { save("lowLimit", lowLimit) } }
    @Published var highLimit: Double { didSet { save("highLimit", highLimit) } }
    @Published var refreshMinutes: Int { didSet { save("refreshMinutes", refreshMinutes) } }
    @Published var language: AppLanguage {
        didSet { L10n.choice = language; save("language", language.rawValue); AppLanguage.applyToBundles(defaults: defaults) }
    }
    /// Writes the latest-reading summary for the desktop widget (on by default; off deletes it).
    @Published var shareWithWidget: Bool { didSet { save("shareWithWidget", shareWithWidget) } }
    @Published var technicalNotifications: Bool { didSet { save("technicalNotifications", technicalNotifications) } }
    // Display toggles; all on by default.
    @Published var colorOutOfRange: Bool { didSet { save("colorOutOfRange", colorOutOfRange) } }
    @Published var menuBarTrend: Bool { didSet { save("menuBarTrend", menuBarTrend) } }
    @Published var showTimeInRange: Bool { didSet { save("showTimeInRange", showTimeInRange) } }
    @Published var showSmartGuard: Bool { didSet { save("showSmartGuard", showSmartGuard) } }
    @Published var showDeviceStatus: Bool { didSet { save("showDeviceStatus", showDeviceStatus) } }
    @Published var showSensorWarnings: Bool { didSet { save("showSensorWarnings", showSensorWarnings) } }
    @Published var showConnectionWarnings: Bool { didSet { save("showConnectionWarnings", showConnectionWarnings) } }
    @Published var showTargetBand: Bool { didSet { save("showTargetBand", showTargetBand) } }
    @Published var showRangePoints: Bool { didSet { save("showRangePoints", showRangePoints) } }
    @Published var showBolusMeals: Bool { didSet { save("showBolusMeals", showBolusMeals) } }
    @Published var showAutoCorrections: Bool { didSet { save("showAutoCorrections", showAutoCorrections) } }
    @Published var showGlucoseStats: Bool { didSet { save("showGlucoseStats", showGlucoseStats) } }
    @Published var menuBarSparkline: Bool { didSet { save("menuBarSparkline", menuBarSparkline) } }
    /// Off by default: the pump limits seen on a Flex were alert limits (70–200), not a target.
    @Published var usePumpLimits: Bool { didSet { save("usePumpLimits", usePumpLimits) } }
    @Published private(set) var diagnosticsEnabled: Bool = Diagnostics.isEnabled

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let low = defaults.double(forKey: "lowLimit"), high = defaults.double(forKey: "highLimit")
        let minutes = defaults.integer(forKey: "refreshMinutes")
        lowLimit = (50...120).contains(low) ? low : GlucoseRange.defaultLow
        highLimit = (120...300).contains(high) ? high : GlucoseRange.defaultHigh
        refreshMinutes = Self.intervals.contains(minutes) ? minutes : 10
        let storedLanguage = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        language = storedLanguage
        L10n.choice = storedLanguage
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        technicalNotifications = flag("technicalNotifications")
        shareWithWidget = flag("shareWithWidget")
        colorOutOfRange = flag("colorOutOfRange")
        menuBarTrend = flag("menuBarTrend")
        showTimeInRange = flag("showTimeInRange")
        showSmartGuard = flag("showSmartGuard")
        showDeviceStatus = flag("showDeviceStatus")
        showSensorWarnings = flag("showSensorWarnings")
        showConnectionWarnings = flag("showConnectionWarnings")
        showTargetBand = flag("showTargetBand")
        showRangePoints = flag("showRangePoints")
        showBolusMeals = flag("showBolusMeals")
        showAutoCorrections = flag("showAutoCorrections")
        showGlucoseStats = flag("showGlucoseStats")
        menuBarSparkline = flag("menuBarSparkline")
        usePumpLimits = defaults.object(forKey: "usePumpLimits") as? Bool ?? false
    }

    func setDiagnostics(_ enabled: Bool) {
        if enabled { Diagnostics.enable() } else { Diagnostics.disable() }
        diagnosticsEnabled = Diagnostics.isEnabled
    }

    /// Target limits in mg/dL actually used for colours, band and dots.
    func target(for snapshot: Snapshot?) -> (low: Double, high: Double) {
        GlucoseRange.effective(manualLow: lowLimit, manualHigh: highLimit, pump: snapshot?.pumpLimits, usePump: usePumpLimits)
    }

    var refreshInterval: TimeInterval { TimeInterval(refreshMinutes * 60) }

    func resetRange() {
        lowLimit = GlucoseRange.defaultLow
        highLimit = GlucoseRange.defaultHigh
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}

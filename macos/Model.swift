import Foundation

struct Reading: Decodable, Identifiable {
    let timestamp: String
    let glucose: Double
    /// Parsed once: the chart reads every date on each redraw.
    let date: Date?
    var id: String { timestamp }

    init(timestamp: String, glucose: Double) {
        self.timestamp = timestamp
        self.glucose = glucose
        self.date = Snapshot.parseDate(timestamp)
    }
    private enum CodingKeys: String, CodingKey { case timestamp, glucose }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(timestamp: try container.decode(String.self, forKey: .timestamp),
                  glucose: try container.decode(Double.self, forKey: .glucose))
    }
}

struct ChartPoint: Identifiable {
    let date: Date
    let glucose: Double
    var id: Date { date }
}

struct Snapshot: Decodable {
    let glucose: Double?
    let unit: String?
    let timestamp: String?
    let trend: String?
    let activeInsulin: Double?
    let history: [Reading]
    let synthetic: Bool?
    // Optional device status; field names confirmed on a real Flex payload (2026-11-07).
    var reservoirUnits: Double? = nil
    /// CareLink's own fill level (0–100); briefly -1 right after a set change, dropped then.
    var reservoirPercent: Double? = nil
    var pumpBatteryPercent: Double? = nil
    var sensorHoursLeft: Double? = nil
    // CareLink 24 h statistics and status, confirmed on a real Flex payload (2026-11-07).
    var timeInRange: TimeInRange? = nil
    var smartGuardState: String? = nil
    var safeBasalMinutes: Double? = nil
    var phoneConnected: Bool? = nil
    var pumpInRange: Bool? = nil
    var pumpSuspended: Bool? = nil
    var pumpCharging: Bool? = nil
    var sensorStateCode: String? = nil
    var systemStatusCode: String? = nil
    var infusionStatusCode: String? = nil
    /// Minutes until the infusion set change (confirmed in minutes on a real Flex payload:
    /// 4319 right after a 3-day set change, decreasing in real time).
    var infusionMinutesLeft: Double? = nil
    var markers: [TherapyMarker] = []
    /// Low/high glucose limits configured on the pump, in mg/dL (`limits[0]`; on a real Flex
    /// payload they were 70–200, i.e. the alert limits rather than a therapy target).
    var pumpLimits: ClosedRange<Double>? = nil

    enum CodingKeys: String, CodingKey {
        case glucose, unit, timestamp, trend, history, synthetic
        case activeInsulin = "active_insulin_units"
        case reservoirUnits = "reservoir_units", pumpBatteryPercent = "pump_battery_percent"
        case sensorHoursLeft = "sensor_hours_left"
    }

    // Formatters are expensive to create and parseDate runs for every reading on each redraw;
    // ISO8601DateFormatter is thread-safe once configured.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }

    var sensorDate: Date? { timestamp.flatMap(Self.parseDate) }
    var knownUnit: Bool { unit == "mg/dL" || unit == "mmol/L" }
    var glucoseText: String {
        guard knownUnit, let glucose, glucose.isFinite, glucose > 0 else { return "—" }
        return String(format: unit == "mmol/L" ? "%.1f" : "%.0f", glucose)
    }
    /// CareLink trend normalized. A real Flex payload uses UP_DOUBLE (confirmed 2026-11-08);
    /// DOUBLE_UP from third-party notes is still accepted.
    var normalizedTrend: String? {
        guard let trend else { return nil }
        let aliases = ["DOUBLE_UP":"UP_DOUBLE", "TRIPLE_UP":"UP_TRIPLE",
                       "DOUBLE_DOWN":"DOWN_DOUBLE", "TRIPLE_DOWN":"DOWN_TRIPLE"]
        return aliases[trend] ?? trend
    }
    var trendSymbol: String {
        switch normalizedTrend {
        case "UP": return "↑"
        case "UP_DOUBLE": return "↑↑"
        case "UP_TRIPLE": return "↑↑↑"
        case "DOWN": return "↓"
        case "DOWN_DOUBLE": return "↓↓"
        case "DOWN_TRIPLE": return "↓↓↓"
        default: return "→"
        }
    }
    var trendDescription: String {
        switch normalizedTrend {
        case "UP", "UP_DOUBLE", "UP_TRIPLE": return tr("Tendência a subir")
        case "DOWN", "DOWN_DOUBLE", "DOWN_TRIPLE": return tr("Tendência a descer")
        default: return tr("Sem seta de tendência reportada")
        }
    }
    var points: [ChartPoint] {
        guard knownUnit else { return [] }
        return history.compactMap { item in
            guard let date = item.date, item.glucose.isFinite, item.glucose > 0 else { return nil }
            return ChartPoint(date: date, glucose: item.glucose)
        }.sorted { $0.date < $1.date }
    }
    var hasDeviceStatus: Bool {
        reservoirUnits != nil || pumpBatteryPercent != nil || sensorHoursLeft != nil
            || pumpSuspended == true || pumpCharging == true || infusionWarning != nil || infusionMinutesLeft != nil
    }

    /// Mean, variability and GMI of the history (needs at least 1 h of readings).
    var glucoseStats: GlucoseStats? { GlucoseStats(points.map(\.glucose), mmol: unit == "mmol/L") }

    /// Mean of the 24 h history in the display unit.
    var averageGlucose: Double? {
        let values = points.map(\.glucose)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Localized SmartGuard status; unknown codes are shown as received.
    var smartGuardText: String? {
        guard let state = smartGuardState, !state.isEmpty else { return nil }
        switch state {
        case "AUTO_BASAL": return tr("Ativo")
        case "SAFE_BASAL":
            guard let minutes = safeBasalMinutes, minutes > 0 else { return tr("Basal segura") }
            return tr("Basal segura (%@min)", "\(Int(minutes))")
        case "FEATURE_OFF": return tr("Desligado (manual)")
        default: return state
        }
    }

    /// Sensor/system status worth showing; nil when CareLink reports no error.
    /// Codes from third-party notes; only NO_ERROR_MESSAGE was seen on a real payload.
    var sensorWarning: String? {
        let quiet: Set<String> = ["NO_ERROR_MESSAGE", ""]
        guard let code = [sensorStateCode, systemStatusCode].compactMap({ $0 }).first(where: { !quiet.contains($0) })
        else { return nil }
        switch code {
        case "WARM_UP": return tr("Sensor a aquecer")
        case "CHANGE_SENSOR": return tr("Trocar sensor")
        case "CALIBRATION_REQUIRED": return tr("Calibração necessária")
        case "DO_NOT_CALIBRATE": return tr("Não calibrar agora")
        case "SG_BELOW_40_MGDL": return tr("Sensor abaixo de 40 mg/dL")
        default: return tr("Sensor: %@", code)
        }
    }
    /// How close the sensor is to its end (thresholds in `LifeRule.sensor`).
    var sensorLife: LifeLevel { LifeRule.sensor.level(hoursLeft: sensorHoursLeft) }
    /// Infusion set: END_OF_LIFE counts as critical; otherwise `LifeRule.infusion`.
    var infusionLife: LifeLevel {
        infusionWarning != nil ? .critical : LifeRule.infusion.level(hoursLeft: infusionTimeLeft.map { $0 / 60 })
    }

    /// Remaining infusion set time while the set is in use; nil once it needs changing.
    var infusionTimeLeft: Double? { infusionWarning == nil ? infusionMinutesLeft : nil }
    /// Infusion set status. END_OF_LIFE on a real Flex payload matched a set due for change (user-confirmed 2026-11-07).
    var infusionWarning: String? { infusionStatusCode == "END_OF_LIFE" ? tr("Trocar conjunto") : nil }

    /// Possible cause for an old reading; nil while connected or unknown. Shown only when the
    /// reading is stale. conduitSensorInRange is ignored: it is false on a Flex with fresh data.
    var connectionWarning: String? {
        if phoneConnected == false { return tr("Telemóvel sem ligação ao CareLink") }
        if pumpInRange == false { return tr("Bomba fora do alcance do telemóvel") }
        return nil
    }

    /// Glucose converted to mg/dL for range classification; nil for unknown units.
    var glucoseMgdl: Double? {
        guard knownUnit, let glucose, glucose.isFinite, glucose > 0 else { return nil }
        return unit == "mmol/L" ? glucose * GlucoseRange.mmolFactor : glucose
    }
    func range(low: Double, high: Double) -> GlucoseRange? {
        glucoseMgdl.map { GlucoseRange.classify(mgdl: $0, low: low, high: high) }
    }

    /// Compact duration for consumables, e.g. "2d 23h", "5h", "<1h".
    static func compactDuration(hours: Double) -> String {
        let total = Int(hours.rounded(.down))
        if total < 1 { return "<1h" }
        return total >= 24 ? "\(total / 24)d \(total % 24)h" : "\(total)h"
    }

    /// Localized age of a reading, e.g. "7min ago" ("há 7min" in Portuguese).
    static func ageText(of date: Date, now: Date) -> String {
        let minutes = Int((now.timeIntervalSince(date) / 60).rounded(.down))
        if minutes < 0 { return tr("no futuro") }
        if minutes < 1 { return tr("agora") }
        if minutes < 60 { return tr("há %@min", "\(minutes)") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? tr("há %@h", "\(hours)") : tr("há %@h %@min", "\(hours)", "\(rest)")
    }

    /// Localized time until a future moment, e.g. "in 4min" ("em 4min" in Portuguese).
    static func untilText(of date: Date, now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return tr("agora") }
        if minutes < 60 { return tr("em %@min", "\(minutes)") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? tr("em %@h", "\(hours)") : tr("em %@h %@min", "\(hours)", "\(rest)")
    }

    static let staleAge: TimeInterval = 900
    /// Why the reading should not be trusted as current, or nil when it is recent.
    func staleReason(at now: Date) -> String? {
        guard let date = sensorDate else { return tr("Hora da leitura indisponível") }
        let age = now.timeIntervalSince(date)
        if age < -300 { return tr("Hora da leitura à frente do relógio do Mac") }
        if age > Self.staleAge { return tr("Última leitura %@", Self.ageText(of: date, now: now)) }
        return nil
    }
    func isStale(at now: Date) -> Bool { staleReason(at: now) != nil }
}

struct RefreshGate {
    static let defaultInterval: TimeInterval = 600
    static let timeout: TimeInterval = 120
    private(set) var interval: TimeInterval = RefreshGate.defaultInterval
    private(set) var started: Date?
    private(set) var nextDue: Date?
    private var lastBegin: Date?
    var running: Bool { started != nil }

    mutating func begin(at now: Date) -> Bool {
        guard !running else { return false }
        started = now
        lastBegin = now
        nextDue = now.addingTimeInterval(interval)
        return true
    }
    mutating func finish() { started = nil }
    static let retryDelay: TimeInterval = 60
    /// After a failed fetch (e.g. network not up yet after wake), try again in about a minute.
    mutating func retrySoon(at now: Date) {
        let retry = now.addingTimeInterval(Self.retryDelay)
        if nextDue.map({ retry < $0 }) ?? true { nextDue = retry }
    }
    /// Changes the interval; the next refresh is rescheduled from the last start.
    mutating func setInterval(_ value: TimeInterval) {
        guard value >= 300 else { return }
        interval = value
        if let lastBegin { nextDue = lastBegin.addingTimeInterval(value) }
    }
    static let staleRetryGap: TimeInterval = 120
    static let staleRetryWindow: TimeInterval = 1800
    /// Early refresh when the reading just became old (likely upload delay): at most once
    /// every 2 min, only while the reading is 15–30 min old. Older data waits for the interval.
    func staleRetryDue(readingAge: TimeInterval?, at now: Date) -> Bool {
        guard !running, let age = readingAge, age > Snapshot.staleAge, age <= Self.staleRetryWindow else { return false }
        return lastBegin.map { now.timeIntervalSince($0) >= Self.staleRetryGap } ?? true
    }
    func isDue(at now: Date) -> Bool { !running && (nextDue == nil || now >= nextDue!) }
    func shouldForceKill(at now: Date) -> Bool {
        started.map { now.timeIntervalSince($0) >= Self.timeout + 5 } ?? false
    }
    func hasTimedOut(at now: Date) -> Bool {
        started.map { now.timeIntervalSince($0) >= Self.timeout } ?? false
    }
}

enum GlucoseRange: Equatable {
    case veryLow, low, inRange, high
    static let mmolFactor = 18.0182
    static let veryLowLimit = 54.0
    static let defaultLow = 70.0
    static let defaultHigh = 180.0

    static func classify(mgdl: Double, low: Double, high: Double) -> GlucoseRange {
        if mgdl < veryLowLimit { return .veryLow }
        if mgdl < low { return .low }
        if mgdl > high { return .high }
        return .inRange
    }
}

/// CareLink's own 24 h distribution (percentages that sum to about 100).
struct TimeInRange: Equatable {
    let inRange: Double
    let below: Double
    let above: Double
    static let goal = 70.0
    init?(inRange: Double?, below: Double?, above: Double?) {
        guard let inRange, let below, let above,
              [inRange, below, above].allSatisfy({ (0...100).contains($0) }),
              abs(inRange + below + above - 100) <= 2 else { return nil }
        self.inRange = inRange; self.below = below; self.above = above
    }
    var meetsGoal: Bool { inRange >= Self.goal }
}

/// Bolus or meal entry from CareLink markers. Read-only display data.
struct TherapyMarker: Identifiable, Equatable {
    enum Kind: String { case bolus, autoCorrection, meal }
    let kind: Kind
    let date: Date
    let amount: Double
    var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
    var title: String {
        switch kind {
        case .bolus: return tr("Bólus")
        case .autoCorrection: return tr("Correção automática")
        case .meal: return tr("Hidratos")
        }
    }
    var amountText: String {
        let unit = kind == .meal ? "g" : "u"
        return "\(amount.formatted(.number.precision(.fractionLength(0...2)).locale(L10n.locale)))\(unit)"
    }
}

/// How close a consumable (sensor, infusion set) is to its end.
enum LifeLevel: Int, Comparable {
    case normal = 0, warning, critical
    static func < (lhs: LifeLevel, rhs: LifeLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct LifeRule {
    let warningHours: Double
    let criticalHours: Double
    /// Sensor: orange under 24 h, red under 6 h. Infusion set: under 12 h and 2 h.
    static let sensor = LifeRule(warningHours: 24, criticalHours: 6)
    static let infusion = LifeRule(warningHours: 12, criticalHours: 2)
    func level(hoursLeft: Double?) -> LifeLevel {
        guard let hours = hoursLeft else { return .normal }
        if hours < criticalHours { return .critical }
        if hours < warningHours { return .warning }
        return .normal
    }
}

enum Consumable: Equatable { case sensor, infusion }

/// Technical (not clinical) alerts, sent once per episode.
struct TechnicalAlerts {
    enum Alert: Equatable {
        case sessionExpired
        case noRecentData(minutes: Int)
        /// A consumable entered a worse level; hours left nil when it already needs changing.
        case consumableEnding(Consumable, LifeLevel, hoursLeft: Double?)
    }
    /// Last notified levels; persisted by the store so a relaunch does not repeat them.
    private(set) var sensorLevel = LifeLevel.normal
    private(set) var infusionLevel = LifeLevel.normal

    init(sensorLevel: LifeLevel = .normal, infusionLevel: LifeLevel = .normal) {
        self.sensorLevel = sensorLevel
        self.infusionLevel = infusionLevel
    }

    /// Notifies when a level gets worse (normal → warning → critical); a new sensor or set
    /// (level back to normal) re-arms it. Unknown hours keep the previous state.
    mutating func evaluateLife(sensor: LifeLevel, sensorHours: Double?,
                               infusion: LifeLevel, infusionHours: Double?) -> [Alert] {
        var alerts: [Alert] = []
        if sensorHours != nil {
            if sensor > sensorLevel { alerts.append(.consumableEnding(.sensor, sensor, hoursLeft: sensorHours)) }
            sensorLevel = sensor
        }
        if infusionHours != nil || infusion == .critical {
            if infusion > infusionLevel { alerts.append(.consumableEnding(.infusion, infusion, hoursLeft: infusionHours)) }
            infusionLevel = infusion
        }
        return alerts
    }
    static let noDataAge: TimeInterval = 1800
    private var sessionSent = false
    private var noDataSent = false

    /// fetchedRecently guards against false alarms right after sleep, before a refresh lands.
    mutating func evaluate(readingAge: TimeInterval?, sessionExpired: Bool, fetchedRecently: Bool) -> [Alert] {
        var alerts: [Alert] = []
        if sessionExpired {
            if !sessionSent { sessionSent = true; alerts.append(.sessionExpired) }
            return alerts
        }
        sessionSent = false
        guard let age = readingAge else { return alerts }
        if age <= Self.noDataAge { noDataSent = false }
        else if fetchedRecently && !noDataSent {
            noDataSent = true
            alerts.append(.noRecentData(minutes: Int(age / 60)))
        }
        return alerts
    }
}

/// Summary statistics over the readings, in the display unit.
struct GlucoseStats: Equatable {
    let mean: Double
    let standardDeviation: Double
    /// Coefficient of variation in %; below 36 % is usually considered stable.
    let coefficientOfVariation: Double
    /// Glucose Management Indicator (%), 3.31 + 0.02392 × mean mg/dL. Clinically meant for
    /// 14+ days of data; over 24 h it is only indicative.
    let gmi: Double

    init?(_ values: [Double], mmol: Bool) {
        guard values.count >= 12 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        self.mean = mean
        standardDeviation = variance.squareRoot()
        coefficientOfVariation = mean > 0 ? standardDeviation / mean * 100 : 0
        let meanMgdl = mmol ? mean * GlucoseRange.mmolFactor : mean
        gmi = 3.31 + 0.02392 * meanMgdl
    }
}

extension GlucoseRange {
    /// Target limits in mg/dL: the pump's limits when chosen and available, else the manual ones.
    static func effective(manualLow: Double, manualHigh: Double, pump: ClosedRange<Double>?,
                          usePump: Bool) -> (low: Double, high: Double) {
        if usePump, let pump { return (pump.lowerBound, pump.upperBound) }
        return (manualLow, manualHigh)
    }
}

/// Normalised polyline for the menu bar mini chart (last hours of readings).
enum Sparkline {
    static let hours: Double = 3
    /// Minimum vertical span in mg/dL so small wiggles are not exaggerated.
    static let minimumSpanMgdl: Double = 60

    static func path(_ points: [ChartPoint], width: Double, height: Double, mmol: Bool) -> [CGPoint] {
        guard let last = points.last?.date else { return [] }
        let start = last.addingTimeInterval(-hours * 3600)
        let window = points.filter { $0.date >= start }
        guard window.count >= 2 else { return [] }
        let values = window.map(\.glucose)
        let minimumSpan = mmol ? minimumSpanMgdl / GlucoseRange.mmolFactor : minimumSpanMgdl
        var low = values.min()!, high = values.max()!
        if high - low < minimumSpan {
            let middle = (high + low) / 2
            low = middle - minimumSpan / 2; high = middle + minimumSpan / 2
        }
        let duration = hours * 3600
        return window.map { point in
            let x = (point.date.timeIntervalSince(start) / duration) * width
            let y = (point.glucose - low) / (high - low) * height
            return CGPoint(x: x, y: y)
        }
    }
}

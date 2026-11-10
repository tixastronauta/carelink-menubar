import Foundation
import os

/// Latest-reading summary shared between the app (writer) and the widget extension (reader)
/// through the App Group container. Written only after consent; one file, overwritten on every
/// refresh and deleted on logout, consent withdrawal or when sharing is turned off.
/// Contains health data, never tokens. New fields are optional so older files still decode.
struct WidgetSummary: Codable, Equatable {
    var glucoseText: String
    var unit: String
    var trendSymbol: String
    var readingDate: Date?
    /// "in", "low", "veryLow", "high" for colouring; nil when the reading was already old.
    var range: String?
    var updated: Date
    /// "pt" or "en": the app's language, so the widget matches it.
    var language: String? = nil
    /// Readings of the last 3 h in the display unit, oldest first.
    var points: [WidgetPoint]? = nil
    /// Target range in the display unit, for the chart band.
    var targetLow: Double? = nil
    var targetHigh: Double? = nil
    /// CareLink's 24 h time in range, in %.
    var timeInRange: Double? = nil
    var timeBelow: Double? = nil
    var timeAbove: Double? = nil
    /// Large widget extras (same values as the panel).
    var activeInsulin: Double? = nil
    var reservoirUnits: Double? = nil
    var pumpBatteryPercent: Double? = nil
    var infusionMinutesLeft: Double? = nil
    var infusionChange: Bool? = nil
    var sensorHoursLeft: Double? = nil
}

struct WidgetPoint: Codable, Equatable {
    var date: Date
    var value: Double
}

enum WidgetTimeline {
    /// A reading older than this is shown as stale.
    static let staleAge: TimeInterval = 900
    /// Most per-minute entries in one timeline. WidgetKit renders every entry ahead of time and the
    /// app replaces the timeline on each new reading (about every 5 min), so a long per-minute
    /// timeline is mostly rendered and thrown away (the 0.3.1 widget used 60 and spiked the CPU).
    static let maxMinuteEntries = 10

    /// Entry dates and when WidgetKit should ask for the next timeline.
    struct Plan: Equatable {
        var dates: [Date]
        var reload: Date
    }

    /// Only the moments the widget's text can change. While the reading is recent, one entry per
    /// minute aligned to the reading (the age text counts whole minutes), up to the first stale
    /// minute and at most `maxMinuteEntries`. Once stale, one entry every 5 min for an hour. No
    /// reading: a single entry. Always an explicit reload date (never `.atEnd` on one entry).
    static func plan(start: Date, reading: Date?) -> Plan {
        guard let reading else { return Plan(dates: [start], reload: start.addingTimeInterval(3600)) }
        var dates = [start]
        let age = start.timeIntervalSince(reading)
        if age > staleAge {
            for step in 1...11 { dates.append(start.addingTimeInterval(Double(step) * 300)) }
            return Plan(dates: dates, reload: dates[dates.count - 1].addingTimeInterval(300))
        }
        var next = reading.addingTimeInterval((age / 60).rounded(.down) * 60 + 60)
        while dates.count < maxMinuteEntries {
            dates.append(next)
            if next.timeIntervalSince(reading) > staleAge { break }
            next = next.addingTimeInterval(60)
        }
        return Plan(dates: dates, reload: dates[dates.count - 1].addingTimeInterval(60))
    }

    /// Readings mapped to a unit square for the background curve: x by time (0 = first, 1 = last),
    /// y downwards (0 = top of `domain`, 1 = bottom), clamped. Fewer than two points → empty.
    static func unitPoints(_ points: [WidgetPoint], domain: ClosedRange<Double>) -> [CGPoint] {
        guard points.count >= 2, let first = points.first?.date, let last = points.last?.date else { return [] }
        let span = max(last.timeIntervalSince(first), 1)
        let height = max(domain.upperBound - domain.lowerBound, .ulpOfOne)
        return points.map { point in
            let x = point.date.timeIntervalSince(first) / span
            let y = 1 - (point.value - domain.lowerBound) / height
            return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        }
    }

    /// Same rule as the app: older than 15 min, missing or more than 5 min in the future.
    static func isStale(_ summary: WidgetSummary, at date: Date) -> Bool {
        guard let reading = summary.readingDate else { return true }
        let age = date.timeIntervalSince(reading)
        return age > staleAge || age < -300
    }
    /// Applies the language the app was using when it wrote the summary.
    static func applyLanguage(of summary: WidgetSummary?) {
        switch summary?.language {
        case "en": L10n.choice = .english
        case "pt": L10n.choice = .portuguese
        default: L10n.choice = .system
        }
    }
}

enum SharedStore {
    /// App Group ID (Team-ID prefixed), injected into both Info.plists by the build script.
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "CareLinkAppGroup") as? String }
    /// URL the widget opens on click; the app shows its panel.
    static let openURL = URL(string: "carelinkmenu://open")!
    /// WidgetKit kind of the glucose widget; the app reloads only this one.
    static let widgetKind = "CareLinkGlucose"

    static var fileURL: URL? {
        guard let groupID, !groupID.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        return container.appendingPathComponent("widget-summary.json")
    }

    /// Status only (never values): helps diagnose the app/widget hand-off.
    static let log = Logger(subsystem: "local.tcx.carelink.menu", category: "widget")

    static func write(_ summary: WidgetSummary) {
        guard let url = fileURL else { log.error("widget summary not written: no group container"); return }
        do {
            // `.atomic` stages the file outside the group container, which macOS refuses here.
            // Write a temp file next to it and rename(2) it over the old one (atomic on one volume).
            let temp = url.deletingLastPathComponent().appendingPathComponent(".widget-summary.tmp")
            try JSONEncoder().encode(summary).write(to: temp)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
            guard rename(temp.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            log.info("widget summary written")
        } catch {
            log.error("widget summary write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func read() -> WidgetSummary? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSummary.self, from: data)
    }

    static func delete() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

import Foundation

// Synthetic checks for the widget hand-off (no real data, no App Group access).
@main struct WidgetChecks {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = WidgetSummary(glucoseText: "120", unit: "mg/dL", trendSymbol: "↑", readingDate: now,
                                    range: "in", updated: now, language: "en",
                                    points: [WidgetPoint(date: now, value: 120)], targetLow: 70, targetHigh: 180,
                                    timeInRange: 96)
        let decoded = try JSONDecoder().decode(WidgetSummary.self, from: JSONEncoder().encode(summary))
        precondition(decoded == summary)
        // Files written by the proof of concept (no new fields) must still decode.
        let legacy = #"{"glucoseText":"99","unit":"mg/dL","trendSymbol":"→","range":"in","updated":0}"#
        let old = try JSONDecoder().decode(WidgetSummary.self, from: Data(legacy.utf8))
        precondition(old.points == nil && old.language == nil && old.timeInRange == nil)

        let dates = WidgetTimeline.entryDates(start: now)
        precondition(dates.count == 60 && dates[1].timeIntervalSince(dates[0]) == 60)
        precondition(!WidgetTimeline.isStale(summary, at: now.addingTimeInterval(900)))
        precondition(WidgetTimeline.isStale(summary, at: now.addingTimeInterval(901)))
        precondition(WidgetTimeline.isStale(summary, at: now.addingTimeInterval(-301)))
        precondition(WidgetTimeline.isStale(old, at: now))

        WidgetTimeline.applyLanguage(of: summary)
        precondition(L10n.choice == .english && Snapshot.ageText(of: now, now: now.addingTimeInterval(420)) == "7min ago")
        WidgetTimeline.applyLanguage(of: WidgetSummary(glucoseText: "", unit: "", trendSymbol: "", readingDate: nil,
                                                       range: nil, updated: now, language: "pt"))
        precondition(Snapshot.ageText(of: now, now: now.addingTimeInterval(420)) == "há 7min")
        precondition(SharedStore.openURL.scheme == "carelinkmenu")
        print("PASS: widget summary encoding, legacy decoding, per-minute timeline, staleness, language, open URL")
    }
}

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

        // Fresh reading (30 s old): start, then the reading's next whole minutes, capped at 10 entries.
        let fresh = WidgetTimeline.plan(start: now.addingTimeInterval(30), reading: now)
        precondition(fresh.dates.count == WidgetTimeline.maxMinuteEntries)
        precondition(fresh.dates[1] == now.addingTimeInterval(60) && fresh.dates[9] == now.addingTimeInterval(540))
        precondition(fresh.reload == now.addingTimeInterval(600))
        // 12 min old: minute entries stop at the first stale minute (16 min).
        let ageing = WidgetTimeline.plan(start: now.addingTimeInterval(720), reading: now)
        precondition(ageing.dates.count == 5 && ageing.dates.last == now.addingTimeInterval(960))
        precondition(WidgetTimeline.isStale(summary, at: ageing.dates.last!) && !WidgetTimeline.isStale(summary, at: ageing.dates[3]))
        precondition(ageing.reload == now.addingTimeInterval(1020))
        // Stale: every 5 min for an hour.
        let stale = WidgetTimeline.plan(start: now.addingTimeInterval(1200), reading: now)
        precondition(stale.dates.count == 12 && stale.dates[1].timeIntervalSince(stale.dates[0]) == 300)
        precondition(stale.reload == now.addingTimeInterval(1200 + 3600))
        // No reading: one entry, explicit reload (never .atEnd on a single entry).
        let empty = WidgetTimeline.plan(start: now, reading: nil)
        precondition(empty.dates == [now] && empty.reload == now.addingTimeInterval(3600))
        // Every plan is strictly increasing and reloads after its last entry.
        for plan in [fresh, ageing, stale, empty] {
            precondition(zip(plan.dates, plan.dates.dropFirst()).allSatisfy { $0 < $1 } && plan.reload > plan.dates.last!)
        }

        let curve = WidgetTimeline.unitPoints([WidgetPoint(date: now, value: 70), WidgetPoint(date: now.addingTimeInterval(300), value: 180),
                                               WidgetPoint(date: now.addingTimeInterval(600), value: 400)], domain: 60...190)
        precondition(curve.count == 3 && curve[0].x == 0 && curve[1].x == 0.5 && curve[2].x == 1)
        precondition(abs(curve[0].y - 120.0 / 130) < 1e-9 && abs(curve[1].y - 10.0 / 130) < 1e-9 && curve[2].y == 0)
        precondition(WidgetTimeline.unitPoints([WidgetPoint(date: now, value: 1)], domain: 0...2).isEmpty)

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
        print("PASS: widget summary encoding, legacy decoding, short timeline plan, background curve, staleness, language, open URL")
    }
}

import Charts
import SwiftUI
import WidgetKit

// WidgetKit extension (built into CareLink Menubar.app/Contents/PlugIns). Reads only the shared
// summary written by the app; it has no tokens and never contacts CareLink. Text follows the
// app's language (stored in the summary); clicking opens the app's panel.

private let accent = Color(red: 0.08, green: 0.52, blue: 0.57)

struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
}

struct SummaryProvider: TimelineProvider {
    private static let sample: WidgetSummary = {
        let now = Date()
        let points = (0..<36).map { WidgetPoint(date: now.addingTimeInterval(Double($0 - 35) * 300),
                                                value: 120 + 30 * sin(Double($0) / 6)) }
        return WidgetSummary(glucoseText: "112", unit: "mg/dL", trendSymbol: "→", readingDate: now,
                             range: "in", updated: now, points: points, targetLow: 70, targetHigh: 180,
                             timeInRange: 82, timeBelow: 2, timeAbove: 16, activeInsulin: 0.4,
                             reservoirUnits: 150, pumpBatteryPercent: 80, infusionMinutesLeft: 3000,
                             infusionChange: false, sensorHoursLeft: 60)
    }()

    func placeholder(in context: Context) -> SummaryEntry { SummaryEntry(date: Date(), summary: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        let summary = context.isPreview ? (SharedStore.read() ?? Self.sample) : SharedStore.read()
        completion(SummaryEntry(date: Date(), summary: summary))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        // Few entries: WidgetKit renders each one ahead of time, and the app reloads on every new
        // reading anyway (see WidgetTimeline.plan).
        let summary = SharedStore.read()
        let plan = WidgetTimeline.plan(start: Date(), reading: summary?.readingDate)
        let entries = plan.dates.map { SummaryEntry(date: $0, summary: summary) }
        completion(Timeline(entries: entries, policy: .after(plan.reload)))
    }
}

enum WidgetLayout { case small, medium, large }

struct SummaryView: View {
    let entry: SummaryEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let layout: WidgetLayout = switch family {
        case .systemMedium: .medium
        case .systemLarge, .systemExtraLarge: .large
        default: .small
        }
        SummaryContent(entry: entry, layout: layout)
    }
}

/// Widget layouts. Small and medium draw the real last-3 h readings faintly behind the value;
/// large shows an explicit chart, time in range and consumables.
struct SummaryContent: View {
    let entry: SummaryEntry
    let layout: WidgetLayout

    private var summary: WidgetSummary? { entry.summary }
    private var stale: Bool { summary.map { WidgetTimeline.isStale($0, at: entry.date) } ?? true }
    private var valueColor: Color {
        guard !stale else { return .secondary }
        switch summary?.range {
        case "veryLow": return .red
        case "low", "high": return .orange
        default: return .primary
        }
    }
    private var ageText: String? { summary?.readingDate.map { Snapshot.ageText(of: $0, now: entry.date) } }
    private var tint: Color { stale ? .gray : accent }

    var body: some View {
        // The language must be set before any tr() call in this render.
        let _ = WidgetTimeline.applyLanguage(of: summary)
        Group {
            switch layout {
            case .small: valueColumn
            case .medium: mediumLayout
            case .large: largeLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .monospacedDigit()
        .containerBackground(for: .widget) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if layout != .large { backgroundChart }
            }
        }
        .widgetURL(SharedStore.openURL)
        .environment(\.locale, L10n.locale)
    }

    // MARK: Pieces

    private var header: some View {
        Label("CareLink Menubar", systemImage: "drop.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
    }

    private func valueText(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(summary?.glucoseText ?? "—")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(summary == nil ? Color.primary : valueColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let summary {
                Text(summary.trendSymbol).font(.title3.weight(.medium))
                    .foregroundStyle(stale ? Color.secondary : Color.primary)
            }
        }
    }

    @ViewBuilder private var ageLabel: some View {
        if let ageText {
            Text(ageText).font(.caption.weight(stale ? .semibold : .regular))
                .foregroundStyle(stale ? Color.orange : Color.secondary)
        }
    }

    private var valueColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Spacer(minLength: 0)
            valueText(size: 40)
            if let summary {
                Text(summary.unit).font(.caption).foregroundStyle(.secondary)
                ageLabel
            } else {
                Text(tr("Abre o CareLink Menubar")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    private var tirColor: Color {
        guard let tir = summary?.timeInRange else { return .secondary }
        return tir >= TimeInRange.goal ? .green : .orange
    }

    // MARK: Medium

    private var mediumLayout: some View {
        HStack(alignment: .bottom) {
            valueColumn
            Spacer(minLength: 8)
            if let tir = summary?.timeInRange {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(percent(tir))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(tirColor)
                    Text(tr("na faixa, 24h")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Large

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                header
                Spacer()
                ageLabel
            }
            HStack(alignment: .lastTextBaseline) {
                valueText(size: 52)
                if let unit = summary?.unit { Text(unit).font(.callout).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                if let insulin = summary?.activeInsulin {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(tr("Insulina ativa")).font(.caption).foregroundStyle(.secondary)
                        Text(units(insulin, digits: 0...2)).font(.callout.weight(.semibold))
                    }
                }
            }
            explicitChart.frame(maxHeight: .infinity)
            if let tir = summary?.timeInRange { timeInRangeBlock(tir) }
            consumablesRow
        }
    }

    private var explicitChart: some View {
        Group {
            if let points = summary?.points, points.count >= 2 {
                let domain = yDomain(points)
                let floor = domain.lowerBound
                Chart {
                    if let low = summary?.targetLow, let high = summary?.targetHigh {
                        RectangleMark(yStart: .value("low", low), yEnd: .value("high", high))
                            .foregroundStyle(Color.green.opacity(0.10))
                    }
                    ForEach(points, id: \.date) { point in
                        AreaMark(x: .value("t", point.date), yStart: .value("floor", floor), yEnd: .value("v", point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("t", point.date), y: .value("v", point.value))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(tint)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                .chartYScale(domain: domain)
            } else {
                Color.clear
            }
        }
    }

    private func timeInRangeBlock(_ tir: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(percent(tir)).font(.title3.weight(.semibold)).foregroundStyle(tirColor)
                Text(tr("na faixa, 24h")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let below = summary?.timeBelow { legend(.red, tr("Abaixo"), percent(below)) }
                if let above = summary?.timeAbove { legend(.orange, tr("Acima"), percent(above)) }
            }
            rangeBar(tir)
        }
    }

    /// Below / in range / above as proportional capsules. Kept apart from `timeInRangeBlock` so older
    /// Swift compilers can type-check each view in reasonable time.
    private func rangeBar(_ tir: Double) -> some View {
        let all: [(color: Color, value: Double)] = [(.red, summary?.timeBelow ?? 0), (.green, tir),
                                                    (.orange, summary?.timeAbove ?? 0)]
        let segments = all.filter { $0.value > 0 }
        let total: Double = segments.reduce(0) { $0 + $1.value }
        let gaps = CGFloat(max(0, segments.count - 1)) * 2
        return GeometryReader { (geometry: GeometryProxy) in
            let width: CGFloat = max(0, geometry.size.width - gaps)
            HStack(spacing: 2) {
                ForEach(segments.indices, id: \.self) { (index: Int) in
                    let share: CGFloat = total > 0 ? CGFloat(segments[index].value / total) : 0
                    Capsule().fill(segments[index].color).frame(width: width * share)
                }
            }
        }
        .frame(height: 6)
    }

    private func legend(_ color: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
        .font(.caption2)
    }

    private var consumablesRow: some View {
        HStack(spacing: 0) {
            consumable("cross.vial", summary?.reservoirUnits.map { units($0, digits: 0...0) })
            Spacer(minLength: 6)
            consumable("battery.75", summary?.pumpBatteryPercent.map { "\(Int($0))%" })
            Spacer(minLength: 6)
            consumable("syringe", summary?.infusionChange == true ? tr("Trocar")
                       : summary?.infusionMinutesLeft.map { Snapshot.compactDuration(hours: $0 / 60) },
                       level: summary?.infusionChange == true ? .critical
                           : LifeRule.infusion.level(hoursLeft: summary?.infusionMinutesLeft.map { $0 / 60 }))
            Spacer(minLength: 6)
            consumable("sensor", summary?.sensorHoursLeft.map { Snapshot.compactDuration(hours: $0) },
                       level: LifeRule.sensor.level(hoursLeft: summary?.sensorHoursLeft))
        }
        .font(.caption)
    }

    private func consumable(_ icon: String, _ value: String?, level: LifeLevel = .normal) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(level == .normal ? Color.secondary : lifeColor(level))
            Text(value ?? "—").fontWeight(.semibold).foregroundStyle(lifeColor(level))
        }
        .fixedSize()
    }

    private func lifeColor(_ level: LifeLevel) -> Color {
        switch level {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func units(_ value: Double, digits: ClosedRange<Int>) -> String {
        "\(value.formatted(.number.precision(.fractionLength(digits)).locale(L10n.locale)))u"
    }

    // MARK: Background chart (small and medium)

    /// The real last-3 h readings drawn faintly behind the value, edge to edge. A plain SwiftUI
    /// path (no axes or labels to lay out) costs far less than Swift Charts on every render.
    @ViewBuilder var backgroundChart: some View {
        if let points = summary?.points, points.count >= 2 {
            let curve = WidgetCurve(points: points, domain: yDomain(points))
            ZStack {
                curve.closedArea()
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                curve.stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            // Keep the line in the lower two thirds so the header stays clean.
            .padding(.top, 52)
            .accessibilityHidden(true)
        }
    }

    private func yDomain(_ points: [WidgetPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value) + [summary?.targetLow, summary?.targetHigh].compactMap { $0 }
        let padding = summary?.unit == "mmol/L" ? 0.5 : 10
        return (values.min()! - padding)...(values.max()! + padding)
    }
}

/// Smoothed line through the readings (quadratic curves through the midpoints, so it never
/// overshoots the data, like the monotone interpolation of the large chart).
struct WidgetCurve: Shape {
    let unit: [CGPoint]

    init(points: [WidgetPoint], domain: ClosedRange<Double>) {
        unit = WidgetTimeline.unitPoints(points, domain: domain)
    }

    func path(in rect: CGRect) -> Path {
        let scaled = unit.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        var path = Path()
        guard let first = scaled.first, let last = scaled.last, scaled.count >= 2 else { return path }
        path.move(to: first)
        for index in 1..<scaled.count {
            let previous = scaled[index - 1], point = scaled[index]
            let middle = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
            if index == 1 { path.addLine(to: middle) } else { path.addQuadCurve(to: middle, control: previous) }
        }
        path.addLine(to: last)
        return path
    }

    /// The curve closed down to the bottom edge, for the gradient fill.
    func closedArea() -> some Shape {
        AreaShape(curve: self)
    }

    private struct AreaShape: Shape {
        let curve: WidgetCurve
        func path(in rect: CGRect) -> Path {
            var path = curve.path(in: rect)
            guard let first = curve.unit.first, let last = curve.unit.last else { return path }
            path.addLine(to: CGPoint(x: rect.minX + last.x * rect.width, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

struct GlucoseWidget: Widget {
    var body: some WidgetConfiguration {
        let _ = WidgetTimeline.applyLanguage(of: SharedStore.read())
        return StaticConfiguration(kind: SharedStore.widgetKind, provider: SummaryProvider()) { entry in
            SummaryView(entry: entry)
        }
        .configurationDisplayName("CareLink")
        .description(tr("Glicemia, tendência e gráfico das últimas 3h."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct CareLinkWidgets: WidgetBundle {
    var body: some Widget { GlucoseWidget() }
}

import AppKit
import SwiftUI
import Charts

/// Transient panel UI state owned by the app delegate (e.g. "copied" feedback).
final class PanelState: ObservableObject {
    @Published var justCopied = false
    @Published var flash = false
}

struct CareLinkPopover: View {
    @ObservedObject var store: CareLinkStore
    @ObservedObject var prefs: Preferences
    @ObservedObject var panel: PanelState = PanelState()
    var onSettings: () -> Void = {}
    var onCopy: () -> Void = {}
    var panelHeight: CGFloat = 420
    /// Rendering for the copied image: no header buttons.
    var exporting: Bool = false
    private var hours: Int { store.historyHours }
    private let accent = Color(red: 0.08, green: 0.52, blue: 0.57)

    private var points: [ChartPoint] {
        let all = store.snapshot?.points ?? []
        let end = all.last?.date ?? store.now
        return all.filter { $0.date >= end.addingTimeInterval(-Double(hours) * 3600) }
    }
    private var windowMarkers: [TherapyMarker] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        guard prefs.showBolusMeals else { return [] }
        return (store.snapshot?.markers ?? []).filter {
            $0.date >= first && $0.date <= last && (prefs.showAutoCorrections || $0.kind != .autoCorrection)
        }
    }
    private func markerSymbol(_ marker: TherapyMarker) -> some View {
        let (name, color, size): (String, Color, CGFloat) = switch marker.kind {
        case .bolus: ("drop.fill", .blue, 11)
        case .autoCorrection: ("drop", .blue.opacity(0.7), 8)
        case .meal: ("fork.knife", .orange, 10)
        }
        return Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .help(tr("%@ %@ às %@", marker.title, marker.amountText, marker.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale))))
            .accessibilityLabel("\(marker.title) \(marker.amountText)")
    }
    private var target: (low: Double, high: Double) { prefs.target(for: store.snapshot) }
    private var isMmol: Bool { store.snapshot?.unit == "mmol/L" }
    private func glucoseText(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(isMmol ? 1 : 0)).locale(L10n.locale))) \(store.snapshot?.unit ?? "")"
    }
    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(L10n.locale))
    }
    /// Mean, CV and GMI spread across the card width, with explanations on hover.
    private func statsRow(_ stats: GlucoseStats) -> some View {
        HStack(spacing: 0) {
            stat(tr("Média"), glucoseText(stats.mean), help: tr("info.mean"))
            Spacer(minLength: 8)
            stat("CV", "\(Int(stats.coefficientOfVariation.rounded()))%",
                 help: tr("info.cv", glucoseText(stats.standardDeviation)))
            Spacer(minLength: 8)
            stat("GMI", "\(decimal(stats.gmi))%", help: tr("info.gmi"))
        }
        .font(.caption).monospacedDigit()
    }
    private func stat(_ title: String, _ value: String, help: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
        .fixedSize()
        .help(help)
    }
    private func display(_ mgdl: Double) -> Double { isMmol ? mgdl / GlucoseRange.mmolFactor : mgdl }
    private var glucoseColor: Color {
        guard prefs.colorOutOfRange, let snapshot = store.snapshot, !store.stale else { return .primary }
        switch snapshot.range(low: target.low, high: target.high) {
        case .veryLow: return .red
        case .low, .high: return .orange
        default: return .primary
        }
    }
    private var signedInWithData: Bool { store.isSignedIn && !store.requiresLogin && !store.isSigningIn }
    private func rangeColor(_ value: Double) -> Color {
        let mgdl = isMmol ? value * GlucoseRange.mmolFactor : value
        switch GlucoseRange.classify(mgdl: mgdl, low: target.low, high: target.high) {
        case .veryLow: return .red
        case .low, .high: return .orange
        case .inRange: return accent
        }
    }
    private func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
    private var standardRangeText: String { isMmol ? (L10n.isEnglish ? "3.9–10.0 mmol/L" : "3,9–10,0 mmol/L") : "70–180 mg/dL" }

    /// Time in range gets its own card: it is the key metric after the current value.
    private func timeInRangeCard(_ tir: TimeInRange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                (Text("\(Int(tir.inRange.rounded()))").font(.system(size: 34, weight: .semibold, design: .rounded))
                 + Text("%").font(.system(size: 20, weight: .semibold, design: .rounded)))
                    .monospacedDigit()
                    .foregroundStyle(tir.meetsGoal ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Tempo na faixa")).font(.headline)
                    Text(tr("%@, últimas 24h", standardRangeText)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            GeometryReader { geometry in
                let segments = [(Color.red, tir.below), (Color.green, tir.inRange), (Color.orange, tir.above)]
                    .filter { $0.1 > 0 }
                let total = segments.reduce(0) { $0 + $1.1 }
                let width = max(0, geometry.size.width - 2 * CGFloat(max(0, segments.count - 1)))
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { index in
                        Capsule().fill(segments[index].0)
                            .frame(width: total > 0 ? width * segments[index].1 / total : 0)
                    }
                }
            }
            .frame(height: 10)
            HStack(spacing: 14) {
                legend(.red, tr("Abaixo"), percent(tir.below))
                legend(.orange, tr("Acima"), percent(tir.above))
                Spacer()
                if !prefs.showGlucoseStats, let average = store.snapshot?.averageGlucose {
                    Text(tr("Média %@ %@", average.formatted(.number.precision(.fractionLength(isMmol ? 1 : 0)).locale(L10n.locale)), store.snapshot?.unit ?? ""))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption).monospacedDigit()
            if prefs.showGlucoseStats, let stats = store.snapshot?.glucoseStats {
                Divider().opacity(0.5)
                statsRow(stats)
            }
        }
        .padding(14)
        .modifier(CardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Tempo na faixa %@, abaixo %@, acima %@, últimas 24 horas", percent(tir.inRange), percent(tir.below), percent(tir.above)))
    }
    private func legend(_ color: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
    }

    /// Pump and sensor consumables: four equal columns (caption over value), same card style
    /// as time in range. Missing values show "—" so the columns never shift.
    private func deviceCard(_ snapshot: Snapshot) -> some View {
        let reservoir = snapshot.reservoirUnits.map {
            "\($0.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale)))u"
        }
        let battery = snapshot.pumpBatteryPercent.map { "\(Int($0))%" }
        let infusion: String? = snapshot.infusionWarning != nil ? tr("Trocar")
            : snapshot.infusionTimeLeft.map { hoursText($0 / 60) }
        let sensor = snapshot.sensorHoursLeft.map(hoursText)
        // Space-between: first block on the left padding, last on the right padding, equal gaps.
        return HStack(alignment: .top, spacing: 0) {
            deviceTile(tr("Reservatório"), icon: "cross.vial", value: reservoir,
                       detail: snapshot.reservoirPercent.map { "\(Int($0.rounded()))%" },
                       help: tr("Insulina no reservatório"))
            Spacer(minLength: 8)
            deviceTile(tr("Bateria"), icon: batterySymbol(snapshot), value: battery,
                       help: snapshot.pumpCharging == true ? tr("A carregar") : tr("Bateria da bomba"))
            Spacer(minLength: 8)
            deviceTile(tr("Conjunto"), icon: "syringe", value: infusion,
                       help: lifeHelp(.infusion, snapshot.infusionLife), level: snapshot.infusionLife)
            Spacer(minLength: 8)
            deviceTile(tr("Sensor"), icon: "sensor", value: sensor,
                       help: lifeHelp(.sensor, snapshot.sensorLife), level: snapshot.sensorLife)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .modifier(CardStyle())
    }
    private func deviceTile(_ title: String, icon: String, value: String?, detail: String? = nil,
                            help: String, level: LifeLevel = .normal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // Fixed icon box and row height so every value sits on the same baseline.
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16, height: 14)
                Text(title)
            }
            .font(.caption2).foregroundStyle(.secondary)
            .frame(height: 14)
            (Text(value ?? "—").font(.callout.weight(.semibold))
                .foregroundColor(lifeColor(level))
             + Text(detail.map { "  \($0)" } ?? "").font(.caption).foregroundColor(.secondary))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .fixedSize()
        .help(help)
        .accessibilityElement(children: .combine)
    }
    private func lifeColor(_ level: LifeLevel) -> Color {
        switch level {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }
    private func lifeHelp(_ item: Consumable, _ level: LifeLevel) -> String {
        switch (item, level) {
        case (.sensor, .normal): return tr("Tempo restante do sensor")
        case (.sensor, _): return tr("Trocar sensor em breve")
        case (.infusion, .normal): return tr("Tempo até trocar o conjunto de infusão")
        case (.infusion, _): return tr("Trocar conjunto em breve")
        }
    }
    private func batterySymbol(_ snapshot: Snapshot) -> String {
        if snapshot.pumpCharging == true { return "battery.100.bolt" }
        switch snapshot.pumpBatteryPercent ?? 50 {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func periodChip(_ period: Int) -> some View {
        let selected = store.historyHours == period
        return Button(action: { store.historyHours = period }) {
            Text("\(period)h")
                .font(.caption.weight(selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? accent : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(selected ? accent.opacity(0.16) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func hoursText(_ hours: Double) -> String { Snapshot.compactDuration(hours: hours) }
    private var yDomain: ClosedRange<Double> {
        // Keep the target band visible alongside the readings.
        let values = points.map(\.glucose) + [display(target.low), display(target.high)]
        let padding = store.snapshot?.unit == "mmol/L" ? 1.0 : 20.0
        return max(0, (values.min() ?? 0) - padding)...max(padding, (values.max() ?? 1) + padding)
    }

    var body: some View {
        ScrollView { content }
            .frame(width: 430, height: panelHeight)
            .background(PanelMaterial().ignoresSafeArea())
            // Camera "shutter" flash when the panel image is copied.
            .overlay(Color.white.opacity(panel.flash ? 0.6 : 0).allowsHitTesting(false))
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label {
                    Text("CareLink Menubar").foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "drop.fill").foregroundStyle(accent)
                }
                .font(.headline)
                if prefs.diagnosticsEnabled {
                    // Visible reminder: diagnostics keeps writing responses until turned off.
                    Text(tr("Diagnóstico"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .help(tr("info.diagnosticsbadge"))
                }
                Spacer()
                if !exporting {
                if store.isRefreshing { ProgressView().controlSize(.small) }
                Button(action: { onCopy() }) {
                    Image(systemName: panel.justCopied ? "checkmark" : "camera")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .help(tr(panel.justCopied ? "Copiado" : "Copiar imagem do painel"))
                .accessibilityLabel(tr("Copiar imagem do painel"))
                .disabled(!signedInWithData || store.snapshot == nil)
                Button(action: { store.refresh() }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(tr("Atualizar agora"))
                .accessibilityLabel(tr("Atualizar agora"))
                .disabled(store.isRefreshing || !store.isSignedIn || store.isSigningIn || store.requiresLogin)
                Button(action: { onSettings() }) {
                    Image(systemName: "gearshape").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(tr("Definições"))
                .accessibilityLabel(tr("Definições"))
                }
            }
            if !store.isSignedIn || store.requiresLogin || store.isSigningIn {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr(store.requiresLogin ? "Volta a entrar no CareLink" : "Liga a tua conta CareLink"))
                        .font(.title3.weight(.semibold))
                    Text(tr("Entra na página oficial do CareLink europeu. A sessão fica guardada no Porta-chaves deste Mac."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.isSigningIn {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(tr("A aguardar autenticação…")).font(.caption)
                            Spacer()
                            Button(tr("Cancelar")) { store.cancelLogin() }
                        }
                    } else {
                        Button(tr("Entrar no CareLink")) { store.signIn() }
                            .buttonStyle(.borderedProminent).tint(accent)
                    }
                }
            }
            if store.isSignedIn && !store.requiresLogin && !store.isSigningIn {
            HStack(alignment: .center, spacing: 18) {
                HStack(alignment: .bottom, spacing: 6) {
                        Text(store.snapshot?.glucoseText ?? "—")
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .foregroundStyle(glucoseColor)
                            .monospacedDigit()
                            .minimumScaleFactor(0.75)
                        VStack(spacing: 2) {
                            Text(store.snapshot?.trendSymbol ?? "→")
                                .font(.system(size: 24, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: 64, height: 30)
                                .accessibilityLabel(store.snapshot?.trendDescription ?? tr("Tendência indisponível"))
                            Text(store.snapshot?.unit ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 64)
                        .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tr("Insulina ativa")).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let amount = store.snapshot?.activeInsulin, amount.isFinite, amount >= 0 {
                            Text("\(amount.formatted(.number.precision(.fractionLength(0...3)).locale(L10n.locale)))u")
                                .fontWeight(.medium)
                        } else { Text("—") }
                    }
                    if prefs.showSmartGuard, let smartGuard = store.snapshot?.smartGuardText {
                        HStack {
                            Text("SmartGuard").foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            Text(smartGuard)
                                .fontWeight(.medium)
                                .foregroundStyle(store.snapshot?.smartGuardState == "AUTO_BASAL" ? Color.primary : Color.orange)
                        }
                    }
                    HStack {
                        Text(tr("Leitura do sensor")).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let date = store.snapshot?.sensorDate {
                            Text(Snapshot.ageText(of: date, now: store.now))
                                .help(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
                        } else { Text("—") }
                    }
                    HStack {
                        Text(tr("Última atualização")).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let last = store.lastSuccess {
                            Text(Snapshot.ageText(of: last, now: store.now))
                                .help(last.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
                        } else { Text("—") }
                    }
                    HStack {
                        Text(tr("Próxima atualização")).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let next = store.nextRefresh {
                            Text(Snapshot.untilText(of: next, now: store.now))
                                .help(next.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
                        } else { Text("—") }
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 175)
            }
            }
            if prefs.showTimeInRange, let tir = store.snapshot?.timeInRange, signedInWithData {
                timeInRangeCard(tir)
            }
            if prefs.showDeviceStatus, let snapshot = store.snapshot, snapshot.hasDeviceStatus, signedInWithData {
                deviceCard(snapshot)
            }
            if prefs.showDeviceStatus, store.snapshot?.pumpSuspended == true, signedInWithData {
                Label(tr("Bomba suspensa"), systemImage: "pause.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if prefs.showDeviceStatus, let snapshot = store.snapshot, snapshot.sensorLife == .critical,
               let hours = snapshot.sensorHoursLeft, signedInWithData {
                Label(tr("Sensor termina em %@", Snapshot.compactDuration(hours: hours)), systemImage: "sensor.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.red)
            }
            if prefs.showDeviceStatus, let snapshot = store.snapshot, snapshot.infusionLife == .critical, signedInWithData {
                Label(snapshot.infusionTimeLeft.map { tr("Conjunto termina em %@", Snapshot.compactDuration(hours: $0 / 60)) }
                      ?? tr("Está na altura de trocar o conjunto de infusão"), systemImage: "syringe.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.red)
            }
            if prefs.showSensorWarnings, let sensor = store.snapshot?.sensorWarning, signedInWithData {
                Label(sensor, systemImage: "sensor.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if prefs.showConnectionWarnings, let warning = store.snapshot?.connectionWarning, store.stale, signedInWithData {
                Label(warning, systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let error = store.errorMessage {
                Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = store.snapshot?.staleReason(at: store.now) {
                Label(reason, systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
            }
            if store.isSignedIn && !store.requiresLogin && !store.isSigningIn {
            VStack(alignment: .leading, spacing: 10) {
                // Compact chart header: title left, period chips flush with the chart's right edge.
                HStack(spacing: 4) {
                    Text(tr("Glicemia").uppercased(with: L10n.locale))
                        .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    ForEach([6, 12, 24], id: \.self) { period in
                        periodChip(period)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(tr("Histórico"))
                if points.count >= 2 {
                    Chart {
                        if prefs.showTargetBand {
                            RectangleMark(yStart: .value(tr("Limite inferior"), display(target.low)),
                                          yEnd: .value(tr("Limite superior"), display(target.high)))
                                .foregroundStyle(Color.green.opacity(0.10))
                        }
                        ForEach(points) { point in
                            LineMark(x: .value(tr("Hora"), point.date), y: .value(tr("Glicemia"), point.glucose))
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .foregroundStyle(accent)
                        }
                        ForEach(prefs.showRangePoints ? points.filter { rangeColor($0.glucose) != accent } : []) { point in
                            PointMark(x: .value(tr("Hora"), point.date), y: .value(tr("Glicemia"), point.glucose))
                                .symbolSize(14)
                                .foregroundStyle(rangeColor(point.glucose))
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .chartOverlay { proxy in
                        // Bolus and meal symbols along the bottom of the plot, with hover tooltips.
                        GeometryReader { geometry in
                            if let anchor = proxy.plotFrame {
                                let plot = geometry[anchor]
                                ForEach(windowMarkers) { marker in
                                    if let x = proxy.position(forX: marker.date) {
                                        markerSymbol(marker)
                                            .position(x: plot.minX + x, y: plot.maxY - (marker.kind == .meal ? 22 : 9))
                                    }
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                            AxisValueLabel(format: .dateTime.hour().minute())
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                    .frame(height: 175)
                    .accessibilityLabel(tr("Histórico de glicemia em linha, últimas %@ horas disponíveis", "\(hours)"))
                } else {
                    Text(tr("Histórico insuficiente para desenhar o gráfico."))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 175)
                }
            }
            }
        }
        .padding(22)
        .frame(width: 430)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, L10n.locale)
    }
}

/// Panel card: slightly stronger fill plus a hairline border so cards read clearly on the panel.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
    }
}

/// Panel backing: the dense menu material (adapts to light/dark). The default popover glass was
/// too transparent over busy windows. The arrow is drawn by the system glass and stays lighter;
/// tinting it was tried (vibrantDark appearance, hasFullSizeContent, a view behind the frame) and
/// none reached the arrow.
struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

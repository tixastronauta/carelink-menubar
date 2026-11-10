import AppKit
import SwiftUI

// Settings window: native toolbar tabs, one grouped Form per tab. All text goes through tr()
// so the language can change while the window is open.

private let paneWidth: CGFloat = 480

private struct Pane<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: paneWidth)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.locale, L10n.locale)
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Setting title followed by an ⓘ button: hover shows a tooltip, click shows the full text.
private struct InfoLabel: View {
    let title: String
    let info: String
    init(_ title: String, info: String) { self.title = title; self.info = info }
    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            InfoTip(text: info).frame(width: 15, height: 15)
        }
    }
}

/// AppKit button + NSPopover, so no SwiftUI @State is needed (plain swiftc has no macro plugin).
struct InfoTip: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: tr("Mais informação"))
            ?? NSImage()
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.toggle(_:)))
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.text = text
        button.toolTip = text
        button.setAccessibilityLabel(tr("Mais informação"))
        button.setAccessibilityHelp(text)
    }

    final class Coordinator: NSObject {
        var text = ""
        private let popover = NSPopover()

        @objc func toggle(_ sender: NSButton) {
            if popover.isShown { popover.performClose(nil); return }
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
            label.preferredMaxLayoutWidth = 280
            let size = label.fittingSize
            label.frame = NSRect(x: 12, y: 10, width: size.width, height: size.height)
            let container = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 24, height: size.height + 20))
            container.addSubview(label)
            let controller = NSViewController()
            controller.view = container
            controller.preferredContentSize = container.frame.size
            popover.contentViewController = controller
            popover.behavior = .transient
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }
}

struct GeneralSettings: View {
    @ObservedObject var launch: LaunchAtLogin
    @ObservedObject var prefs: Preferences
    var body: some View {
        Pane {
            Section(tr("Idioma")) {
                Picker(selection: $prefs.language) {
                    Text(tr("Automático (macOS)")).tag(AppLanguage.system)
                    Text("Português").tag(AppLanguage.portuguese)
                    Text("English").tag(AppLanguage.english)
                } label: { InfoLabel(tr("Idioma"), info: tr("info.language")) }
            }
            Section(tr("Arranque")) {
                Toggle(isOn: Binding(get: { launch.isEnabled || launch.requiresApproval }, set: { launch.set($0) })) {
                    InfoLabel(tr("Abrir ao iniciar sessão no Mac"), info: tr("info.launch"))
                }
                if launch.requiresApproval {
                    HStack {
                        Text(tr("Falta aprovar nas Definições do Sistema.")).font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(tr("Abrir Definições do Sistema")) { launch.openSettings() }
                    }
                }
                if let message = launch.message {
                    Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(tr("Atualização")) {
                Picker(selection: $prefs.refreshMinutes) {
                    ForEach(Preferences.intervals, id: \.self) { Text(tr("%@min", "\($0)")).tag($0) }
                } label: { InfoLabel(tr("Atualizar a cada"), info: tr("info.refresh")) }
            }
            Section(tr("Widget")) {
                Toggle(isOn: $prefs.shareWithWidget) {
                    InfoLabel(tr("Mostrar dados no widget da secretária"), info: tr("info.widget"))
                }
            }
            Section(tr("Notificações")) {
                Toggle(isOn: $prefs.technicalNotifications) {
                    InfoLabel(tr("Avisar falhas técnicas"), info: tr("info.notifications"))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launch.reload()
        }
    }
}

struct DisplaySettings: View {
    @ObservedObject var prefs: Preferences
    var body: some View {
        Pane {
            Section(tr("Valor da glicemia")) {
                Toggle(isOn: $prefs.colorOutOfRange) {
                    InfoLabel(tr("Colorir quando está fora da faixa-alvo"), info: tr("info.color"))
                }
                Toggle(tr("Mostrar seta de tendência na barra de menus"), isOn: $prefs.menuBarTrend)
                Toggle(isOn: $prefs.menuBarSparkline) {
                    InfoLabel(tr("Mini-gráfico na barra de menus"), info: tr("info.sparkline"))
                }
            }
            Section(tr("Painel")) {
                Toggle(isOn: $prefs.showTimeInRange) { InfoLabel(tr("Tempo na faixa"), info: tr("info.tir")) }
                Toggle(isOn: $prefs.showGlucoseStats) {
                    InfoLabel(tr("Média, CV e GMI"), info: tr("info.stats"))
                }
                .disabled(!prefs.showTimeInRange)
                .padding(.leading, 16)
                Toggle(isOn: $prefs.showSmartGuard) { InfoLabel(tr("Estado do SmartGuard"), info: tr("info.smartguard")) }
                Toggle(isOn: $prefs.showDeviceStatus) {
                    InfoLabel(tr("Reservatório, bateria, sensor e conjunto"), info: tr("info.device"))
                }
                Toggle(isOn: $prefs.showSensorWarnings) { InfoLabel(tr("Avisos do sensor"), info: tr("info.sensor")) }
                Toggle(isOn: $prefs.showConnectionWarnings) {
                    InfoLabel(tr("Avisos de ligação do telemóvel e da bomba"), info: tr("info.connection"))
                }
                Caption(tr("Os avisos de leitura antiga e de erros de ligação ao CareLink aparecem sempre."))
            }
        }
    }
}

struct ChartSettings: View {
    @ObservedObject var store: CareLinkStore
    @ObservedObject var prefs: Preferences
    private func limitText(_ mgdl: Double) -> String {
        let mmol = (mgdl / GlucoseRange.mmolFactor).formatted(.number.precision(.fractionLength(1)).locale(L10n.locale))
        return "\(Int(mgdl)) mg/dL (\(mmol) mmol/L)"
    }
    var body: some View {
        Pane {
            Section(tr("Faixa-alvo")) {
                Toggle(isOn: $prefs.usePumpLimits) {
                    InfoLabel(tr("Usar os limites de alerta da bomba"), info: tr("info.pumplimits"))
                }
                if prefs.usePumpLimits {
                    LabeledContent(tr("Limites da bomba"), value: store.snapshot?.pumpLimits.map {
                        "\(Int($0.lowerBound))–\(Int($0.upperBound)) mg/dL"
                    } ?? tr("Indisponível"))
                } else {
                    Stepper(value: $prefs.lowLimit, in: 50...120, step: 5) {
                        LabeledContent(tr("Limite inferior"), value: limitText(prefs.lowLimit))
                    }
                    Stepper(value: $prefs.highLimit, in: 120...300, step: 5) {
                        LabeledContent(tr("Limite superior"), value: limitText(prefs.highLimit))
                    }
                }
                HStack {
                    Caption(tr("Usada na banda do gráfico e nas cores. Não altera o tempo na faixa nem gera alertas."))
                    Spacer()
                    if !prefs.usePumpLimits { Button(tr("Repor 70–180")) { prefs.resetRange() } }
                }
            }
            Section(tr("No gráfico")) {
                Toggle(isOn: $prefs.showTargetBand) { InfoLabel(tr("Banda da faixa-alvo"), info: tr("info.band")) }
                Toggle(isOn: $prefs.showRangePoints) {
                    InfoLabel(tr("Pontos nas leituras fora da faixa"), info: tr("info.points"))
                }
                Toggle(isOn: $prefs.showBolusMeals) { InfoLabel(tr("Bólus e refeições"), info: tr("info.markers")) }
                Toggle(isOn: $prefs.showAutoCorrections) {
                    InfoLabel(tr("Correções automáticas do SmartGuard"), info: tr("info.autocorrections"))
                }
                .disabled(!prefs.showBolusMeals)
                // Form only dims the switch; fade the label too so the dependency is obvious.
                .opacity(prefs.showBolusMeals ? 1 : 0.4)
                .padding(.leading, 16)
            }
        }
    }
}

struct AccountSettings: View {
    @ObservedObject var store: CareLinkStore
    @ObservedObject var prefs: Preferences
    var onSignIn: () -> Void
    var onLogout: () -> Void

    private enum State { case signingIn, connected, expired, signedOut }
    private var state: State {
        if store.isSigningIn { return .signingIn }
        if store.isSignedIn { return store.requiresLogin ? .expired : .connected }
        return .signedOut
    }
    private var symbol: String {
        switch state {
        case .signingIn: return "hourglass"
        case .connected: return "checkmark"
        case .expired: return "exclamationmark"
        case .signedOut: return "person.fill"
        }
    }
    private var color: Color {
        switch state {
        case .signingIn: return .blue
        case .connected: return .green
        case .expired: return .orange
        case .signedOut: return .secondary
        }
    }
    private var title: String {
        switch state {
        case .signingIn: return tr("A ligar ao CareLink…")
        case .connected: return tr("Ligado ao CareLink")
        case .expired: return tr("Sessão expirada")
        case .signedOut: return tr("Sem sessão")
        }
    }
    private var subtitle: String {
        switch state {
        case .signingIn: return tr("Conclui o início de sessão na página oficial.")
        case .connected: return store.accountName ?? tr("Conta CareLink")
        case .expired: return tr("Entra novamente para continuar a ver os dados.")
        case .signedOut: return tr("Entra na página oficial do CareLink para ver os teus dados.")
        }
    }

    var body: some View {
        Pane {
            Section {
                // Status at a glance: coloured badge, headline and the account underneath.
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(color.opacity(0.16)).frame(width: 46, height: 46)
                        if state == .signingIn {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: symbol)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(color)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.title3.weight(.semibold))
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if state == .connected, let last = store.lastSuccess {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(tr("Última atualização")).font(.caption).foregroundStyle(.secondary)
                            Text(Snapshot.ageText(of: last, now: store.now)).font(.callout.weight(.medium))
                        }
                        .monospacedDigit()
                    }
                }
                .padding(.vertical, 6)
                HStack {
                    switch state {
                    case .signingIn:
                        Spacer()
                        Button(tr("Cancelar")) { store.cancelLogin() }
                    case .connected:
                        Spacer()
                        Button(tr("Terminar sessão…"), role: .destructive) { onLogout() }
                    case .expired:
                        Button(tr("Terminar sessão…"), role: .destructive) { onLogout() }
                        Spacer()
                        Button(tr("Entrar novamente")) { onSignIn() }.buttonStyle(.borderedProminent)
                    case .signedOut:
                        Spacer()
                        Button(tr("Entrar no CareLink")) { onSignIn() }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

struct AdvancedSettings: View {
    @ObservedObject var store: CareLinkStore
    @ObservedObject var prefs: Preferences
    private func openLogs() {
        try? FileManager.default.createDirectory(at: Diagnostics.directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(Diagnostics.directory)
    }
    private func copyShape() {
        guard let shape = store.payloadShape else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shape.joined(separator: "\n"), forType: .string)
    }
    var body: some View {
        Pane {
            Section(tr("Modo diagnóstico")) {
                Toggle(isOn: Binding(get: { prefs.diagnosticsEnabled }, set: { prefs.setDiagnostics($0) })) {
                    InfoLabel(tr("Guardar respostas do CareLink"), info: tr("info.diagnostics"))
                }
                Caption(tr("Inclui dados de saúde e a tua identidade. Os tokens nunca são guardados."))
                HStack {
                    Button(tr("Abrir pasta dos logs")) { openLogs() }
                    Button(tr("Apagar logs")) { Diagnostics.deleteAll() }
                    Spacer()
                }
            }
            Section(tr("Estrutura do payload")) {
                HStack(spacing: 6) {
                    Button(tr("Copiar estrutura do payload")) { copyShape() }
                        .disabled(store.payloadShape == nil)
                    InfoTip(text: tr("info.shape")).frame(width: 15, height: 15)
                    Spacer()
                }
            }
        }
    }
}

struct AboutSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var updater: AppUpdater
    var onWithdrawConsent: () -> Void = {}
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
    static let projectURL = URL(string: "https://github.com/tixastronauta/carelink-menubar")!
    var body: some View {
        Pane {
            Section(AppVariant.current.displayName) {
                LabeledContent(tr("Versão"), value: version)
                LabeledContent(tr("Licença"), value: "AGPL-3.0")
                HStack {
                    Link(tr("Código-fonte no GitHub"), destination: Self.projectURL)
                    Spacer()
                    Link(tr("Projeto original"), destination: URL(string: "https://github.com/ondrej1024/carelink-python-client")!)
                }
                Caption(tr("App não oficial, sem afiliação à MiniMed (antiga Medtronic Diabetes). Apenas leitura: não controla a bomba nem substitui a app MiniMed. Confirma sempre os valores na app oficial."))
            }
            Section(tr("Atualizações")) {
                if updater.isAvailable {
                    Toggle(isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 })) {
                        InfoLabel(tr("Procurar atualizações automaticamente"), info: tr("info.updates"))
                    }
                    HStack {
                        Text(updater.lastCheck.map {
                            tr("Última verificação: %@", $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
                        } ?? tr("Ainda não verificado")).foregroundStyle(.secondary)
                        Spacer()
                        Button(tr("Procurar agora")) { updater.showUpdate() }
                    }
                } else {
                    Caption(tr("As atualizações automáticas estão desativadas nesta versão de desenvolvimento."))
                }
            }
            Section(tr("Consentimento")) {
                LabeledContent(tr("Aceite em"), value: Consent.acceptedAt.map {
                    $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))
                } ?? "—")
                HStack {
                    Spacer()
                    Button(tr("Retirar consentimento…"), role: .destructive) { onWithdrawConsent() }
                }
                Caption(tr("Retirar termina a sessão, apaga os ficheiros guardados pela app e fecha-a."))
            }
        }
    }
}

/// Toolbar-style tabs. Each pane reports its SwiftUI height as preferredContentSize and
/// NSTabViewController resizes the window when switching tabs.
final class SettingsTabController: NSTabViewController {
    /// Portuguese source titles, translated with tr() on every relabel.
    private var titleKeys: [String] = []

    func addPane<V: View>(_ titleKey: String, symbol: String, _ view: V) {
        let host = NSHostingController(rootView: view)
        // Automatic sizing is off (it makes fittingSize 0 and fights the tab transition);
        // the height is measured explicitly with sizeThatFits.
        host.sizingOptions = []
        host.title = tr(titleKey)
        Self.measure(host)
        let item = NSTabViewItem(viewController: host)
        item.label = tr(titleKey)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tr(titleKey))
        titleKeys.append(titleKey)
        addTabViewItem(item)
    }

    /// Re-applies translated titles and re-fits the window, e.g. after a language change.
    func relabel() {
        for (item, key) in zip(tabViewItems, titleKeys) {
            item.label = tr(key)
            item.viewController?.title = tr(key)
        }
        guard let window = view.window else { return }
        let item = tabViewItems[selectedTabViewItemIndex]
        window.title = item.label
        DispatchQueue.main.async { [weak self] in
            guard let self, let controller = item.viewController, let window = self.view.window else { return }
            Self.measure(controller)
            let top = window.frame.maxY
            window.setContentSize(controller.preferredContentSize)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
    }

    /// Re-fits the window when the visible tab's content changes height (e.g. sign-in state).
    func refit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.view.window,
                  let controller = self.tabViewItems[self.selectedTabViewItemIndex].viewController else { return }
            Self.measure(controller)
            let size = controller.preferredContentSize
            guard abs(window.contentLayoutRect.height - size.height) > 0.5 else { return }
            let top = window.frame.maxY
            window.setContentSize(size)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
    }

    private static func measure(_ controller: NSViewController) {
        guard let host = controller as? any SizeMeasuring else { return }
        controller.preferredContentSize = NSSize(width: paneWidth, height: ceil(host.measuredHeight(width: paneWidth)))
    }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        // Content can change while hidden (e.g. sign-in state), so re-measure before showing.
        if let controller = tabViewItem?.viewController { Self.measure(controller) }
        super.tabView(tabView, willSelect: tabViewItem)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? ""
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let item = tabViewItems[selectedTabViewItemIndex]
        view.window?.title = item.label
        if let controller = item.viewController, let window = view.window {
            Self.measure(controller)
            // Keep the top edge where the window was placed (setContentSize keeps the bottom).
            let top = window.frame.maxY
            window.setContentSize(controller.preferredContentSize)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
    }
}

private protocol SizeMeasuring { func measuredHeight(width: CGFloat) -> CGFloat }
extension NSHostingController: SizeMeasuring {
    fileprivate func measuredHeight(width: CGFloat) -> CGFloat {
        sizeThatFits(in: NSSize(width: width, height: 10_000)).height
    }
}

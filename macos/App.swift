import AppKit
import WidgetKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var store: CareLinkStore!
    private let launch = LaunchAtLogin()
    private let prefs = Preferences()
    private let notifier = Notifier()
    private var settingsWindow: NSWindow?
    private var settingsTabs: SettingsTabController?

    private var consentWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Must be read now: the launch Apple event is gone once consent is shown.
        let loginLaunch = LaunchAtLogin.launchedAsLoginItem()
        if Consent.isAccepted { startApp(loginLaunch: loginLaunch) }
        else { showConsent() }
    }

    /// Blocks the app until the user accepts; nothing reads CareLink before that.
    private func showConsent() {
        let view = ConsentView(prefs: prefs,
            onAccept: { [weak self] in
                Consent.accept()
                self?.consentWindow?.close()
                self?.consentWindow = nil
                self?.startApp(loginLaunch: false)
            },
            onQuit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize  // window follows the text height per language
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled]
        window.title = "CareLink Menubar"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        consentWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Clears the session and every file the app wrote, forgets consent and quits.
    private func confirmWithdrawConsent() {
        let alert = NSAlert()
        alert.messageText = tr("Retirar o consentimento?")
        alert.informativeText = tr("consent.withdraw")
        alert.alertStyle = .warning
        let confirm = alert.addButton(withTitle: tr("Retirar e sair"))
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: tr("Cancelar"))
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.store.logout()
            self?.prefs.setDiagnostics(false)
            Diagnostics.deleteAllNow()
            SharedStore.delete()
            Consent.reset()
            NSApp.terminate(nil)
        }
        if let window = settingsWindow { alert.beginSheetModal(for: window, completionHandler: handle) }
        else { handle(alert.runModal()) }
    }

    private func startApp(loginLaunch: Bool) {
        Diagnostics.purge()
        store = CareLinkStore()
        store.loginAnchor = { [weak self] in self?.popover.contentViewController?.view.window ?? NSWindow() }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "CL …"
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            button.action = #selector(handleStatusClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.setAccessibilityLabel(tr("CareLink: glicemia e tendência"))
        }
        popover.behavior = .transient
        // Hide the system-drawn arrow: it keeps the lighter system glass and cannot be tinted.
        // Undocumented key, so only set it when the popover still answers to it.
        if popover.responds(to: NSSelectorFromString("setShouldHideAnchor:")) {
            popover.setValue(true, forKey: "shouldHideAnchor")
        }
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: makePopover())
        store.onChange = { [weak self] in
            self?.updateStatus()
            if self?.settingsWindow?.isVisible == true { self?.settingsTabs?.refit() }
        }
        store.setRefreshInterval(prefs.refreshInterval)
        notifier.setUp(requestPermission: prefs.technicalNotifications)
        notifier.onOpen = { [weak self] in self?.showPopover() }
        store.onAlert = { [weak self] alert in
            guard let self, self.prefs.technicalNotifications else { return }
            self.notifier.post(alert)
        }
        var notificationsWereOn = prefs.technicalNotifications
        var lastLanguage = prefs.language
        prefs.onChange = { [weak self] in
            guard let self else { return }
            if self.prefs.language != lastLanguage {
                lastLanguage = self.prefs.language
                self.settingsTabs?.relabel()
            }
            self.store.setRefreshInterval(self.prefs.refreshInterval)
            if self.prefs.technicalNotifications && !notificationsWereOn { self.notifier.requestPermission() }
            notificationsWereOn = self.prefs.technicalNotifications
            self.updateStatus()
            if self.settingsWindow?.isVisible == true { self.settingsTabs?.refit() }
        }
        store.start()
        updateStatus()
        // Show the detail panel on a manual launch so the app is immediately discoverable;
        // keep it closed when macOS opens the app as a login item.
        if !loginLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showPopover() }
        }
    }

    private func updateStatus() {
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)]
        store.showTrendInMenuBar = prefs.menuBarTrend
        if prefs.colorOutOfRange, let snapshot = store.snapshot, !store.stale, store.errorMessage == nil {
            switch snapshot.range(low: prefs.target(for: snapshot).low, high: prefs.target(for: snapshot).high) {
            case .veryLow: attributes[.foregroundColor] = NSColor.systemRed
            case .low, .high: attributes[.foregroundColor] = NSColor.systemOrange
            default: break
            }
        }
        item.button?.attributedTitle = NSAttributedString(string: store.statusTitle, attributes: attributes)
        updateWidget()
        item.button?.image = prefs.menuBarSparkline ? sparkline() : nil
        item.button?.imagePosition = .imageLeft
        var tip = ["CareLink", store.snapshot?.unit ?? tr("sem unidade")]
        if let date = store.snapshot?.sensorDate { tip.append(tr("leitura %@", Snapshot.ageText(of: date, now: store.now))) }
        tip.append(tr("clicar para detalhes"))
        item.button?.toolTip = tip.joined(separator: ", ")
        item.button?.setAccessibilityLabel("CareLink \(store.statusTitle)")
        if popover.isShown { resizePanel() }
    }

    @objc private func handleStatusClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            guard let button = item.button else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            let open = NSMenuItem(title: tr("Abrir"), action: #selector(openPanel), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            menu.addItem(.separator())
            let settings = NSMenuItem(title: tr("Definições…"), action: #selector(showSettings), keyEquivalent: ",")
            settings.target = self
            menu.addItem(settings)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: tr("Sair"), action: #selector(quitApp), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    @objc private func openPanel() {
        // Wait until the context menu has finished dismissing.
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }

    private let panelState = PanelState()
    private static let shutterSound = NSSound(contentsOfFile:
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true)

    private func makePopover(height: CGFloat = 420) -> CareLinkPopover {
        CareLinkPopover(store: store, prefs: prefs, panel: panelState,
                        onSettings: { [weak self] in DispatchQueue.main.async { self?.showSettings() } },
                        onCopy: { [weak self] in self?.copyPanelImage() },
                        panelHeight: height)
    }

    /// Renders the panel (without header buttons) on an opaque background in the current
    /// appearance and puts it on the clipboard as an image, ready to paste in other apps.
    private func copyPanelImage() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = CareLinkPopover(store: store, prefs: prefs, exporting: true).content
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        // Screenshot feedback: brief white flash over the panel and the system capture sound.
        withAnimation(.easeOut(duration: 0.06)) { panelState.flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            withAnimation(.easeIn(duration: 0.35)) { self?.panelState.flash = false }
        }
        Self.shutterSound?.play()
        panelState.justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.panelState.justCopied = false }
    }

    /// Opens Settings next to the panel; the panel stays open while Settings is visible so
    /// toggles can be previewed live.
    @objc private func showSettings() {
        launch.reload()
        popover.behavior = .applicationDefined
        if !popover.isShown { showPopover() }
        if settingsWindow == nil {
            let tabs = SettingsTabController()
            tabs.tabStyle = .toolbar
            tabs.addPane("Geral", symbol: "gearshape", GeneralSettings(launch: launch, prefs: prefs))
            tabs.addPane("Apresentação", symbol: "eye", DisplaySettings(prefs: prefs))
            tabs.addPane("Gráfico", symbol: "chart.xyaxis.line", ChartSettings(store: store, prefs: prefs))
            tabs.addPane("Conta", symbol: "person.crop.circle", AccountSettings(store: store, prefs: prefs,
                onSignIn: { [weak self] in self?.signInFromSettings() },
                onLogout: { [weak self] in self?.confirmLogout() }))
            tabs.addPane("Avançado", symbol: "wrench.and.screwdriver", AdvancedSettings(store: store, prefs: prefs))
            tabs.addPane("Sobre", symbol: "info.circle", AboutSettings(prefs: prefs,
                onWithdrawConsent: { [weak self] in self?.confirmWithdrawConsent() }))
            settingsTabs = tabs
            let window = NSWindow(contentViewController: tabs)
            window.toolbarStyle = .preference
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsWindow, !window.isVisible { placeBesidePanel(window) }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Puts the Settings window to the left of the panel, top-aligned, inside the visible screen.
    private func placeBesidePanel(_ window: NSWindow) {
        guard let panel = popover.contentViewController?.view.window,
              let screen = panel.screen ?? NSScreen.main else { window.center(); return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = max(visible.minX + 8, panel.frame.minX - frame.width - 12)
        frame.origin.y = min(visible.maxY, panel.frame.maxY) - frame.height
        frame.origin.y = max(visible.minY + 8, frame.origin.y)
        window.setFrame(frame, display: false)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        popover.behavior = .transient
    }

    private func confirmLogout() {
        guard let window = settingsWindow else { return }
        let alert = NSAlert()
        alert.messageText = tr("Terminar sessão no CareLink?")
        alert.informativeText = tr("Remove a sessão deste Mac e limpa os dados apresentados. Para voltar a ver dados, tens de entrar novamente.")
        alert.alertStyle = .warning
        let confirm = alert.addButton(withTitle: tr("Terminar sessão"))
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: tr("Cancelar"))
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.store.logout() }
        }
    }

    private func signInFromSettings() {
        // The official login sheet anchors to the panel, as on first launch.
        settingsWindow?.close()
        DispatchQueue.main.async { [weak self] in
            self?.showPopover()
            self?.store.signIn()
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func showPopover() {
        guard let button = item.button else { return }
        resizePanel(force: true)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    private var widgetKey = ""
    /// Shares the latest reading with the widget (consent already given) and asks WidgetKit to
    /// redraw; skipped when nothing changed. Signed out → file deleted.
    private func updateWidget() {
        guard prefs.shareWithWidget, store.isSignedIn, let snapshot = store.snapshot else {
            if widgetKey != "signed-out" {
                SharedStore.log.info("widget summary cleared (sharing: \(self.prefs.shareWithWidget, privacy: .public), signed in: \(self.store.isSignedIn, privacy: .public), data: \(self.store.snapshot != nil, privacy: .public))")
                widgetKey = "signed-out"
                SharedStore.delete()
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        let target = prefs.target(for: snapshot)
        let range: String? = store.stale ? nil : snapshot.range(low: target.low, high: target.high).map {
            switch $0 {
            case .veryLow: return "veryLow"
            case .low: return "low"
            case .high: return "high"
            case .inRange: return "in"
            }
        }
        let mmol = snapshot.unit == "mmol/L"
        let toDisplay = { (mgdl: Double) in mmol ? mgdl / GlucoseRange.mmolFactor : mgdl }
        let recent: [WidgetPoint] = {
            guard let last = snapshot.points.last?.date else { return [] }
            let start = last.addingTimeInterval(-Sparkline.hours * 3600)
            return snapshot.points.filter { $0.date >= start }.map { WidgetPoint(date: $0.date, value: $0.glucose) }
        }()
        let summary = WidgetSummary(glucoseText: snapshot.glucoseText, unit: snapshot.unit ?? "",
                                    trendSymbol: snapshot.trendSymbol, readingDate: snapshot.sensorDate,
                                    range: range, updated: Date(), language: L10n.isEnglish ? "en" : "pt",
                                    points: recent, targetLow: toDisplay(target.low), targetHigh: toDisplay(target.high),
                                    timeInRange: snapshot.timeInRange?.inRange,
                                    timeBelow: snapshot.timeInRange?.below, timeAbove: snapshot.timeInRange?.above,
                                    activeInsulin: snapshot.activeInsulin, reservoirUnits: snapshot.reservoirUnits,
                                    pumpBatteryPercent: snapshot.pumpBatteryPercent,
                                    infusionMinutesLeft: snapshot.infusionTimeLeft,
                                    infusionChange: snapshot.infusionWarning != nil,
                                    sensorHoursLeft: snapshot.sensorHoursLeft)
        let key = [summary.glucoseText, summary.unit, summary.trendSymbol, snapshot.timestamp ?? "", range ?? "-",
                   summary.language ?? "", "\(recent.count)", "\(target.low)-\(target.high)",
                   "\(summary.timeInRange ?? -1)", "\(summary.activeInsulin ?? -1)", "\(summary.reservoirUnits ?? -1)",
                   "\(summary.pumpBatteryPercent ?? -1)", "\(Int((summary.infusionMinutesLeft ?? -1) / 60))",
                   "\(summary.infusionChange ?? false)", "\(Int(summary.sensorHoursLeft ?? -1))"].joined(separator: "|")
        guard key != widgetKey else { return }
        widgetKey = key
        SharedStore.write(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var sparklineKey = ""
    private var sparklineImage: NSImage?
    /// Template image of the last 3 h for the menu bar; redrawn only when the data changes.
    private func sparkline() -> NSImage? {
        guard let snapshot = store.snapshot, !store.stale else { return nil }
        let tail = snapshot.history.suffix(3).map { "\($0.glucose)" }.joined(separator: ",")
        let key = [snapshot.timestamp ?? "", "\(snapshot.history.count)", tail, snapshot.unit ?? "",
                   prefs.language.rawValue].joined(separator: "|")
        if key == sparklineKey { return sparklineImage }
        sparklineKey = key
        let size = NSSize(width: 30, height: 16)
        let path = Sparkline.path(snapshot.points, width: Double(size.width) - 2, height: Double(size.height) - 4,
                                  mmol: snapshot.unit == "mmol/L")
        guard path.count >= 2 else { sparklineImage = nil; return nil }
        let image = NSImage(size: size, flipped: false) { _ in
            let line = NSBezierPath()
            line.lineWidth = 1.4
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            for (index, point) in path.enumerated() {
                let shifted = NSPoint(x: point.x + 1, y: point.y + 2)
                if index == 0 { line.move(to: shifted) } else { line.line(to: shifted) }
            }
            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = tr("Mini-gráfico das últimas 3h")
        sparklineImage = image
        return image
    }

    /// Things that can change the panel height. Measuring renders the whole chart, so it only
    /// happens when this changes, not on the 5 s clock tick.
    private var layoutSignature: String {
        let snapshot = store.snapshot
        return [snapshot?.timestamp ?? "-", "\(snapshot?.markers.count ?? 0)", "\(store.isSignedIn)",
                "\(store.requiresLogin)", "\(store.isSigningIn)", store.errorMessage ?? "-", "\(store.stale)",
                "\(store.historyHours)", "\(prefs.showTimeInRange)", "\(prefs.showSmartGuard)",
                "\(prefs.showDeviceStatus)", "\(prefs.showSensorWarnings)", "\(prefs.showConnectionWarnings)",
                "\(prefs.showGlucoseStats)",
                // Rows that can appear without a new reading (warm-up, pump suspended, lost link).
                snapshot?.sensorWarning ?? "-", "\(snapshot?.pumpSuspended ?? false)",
                snapshot?.connectionWarning ?? "-", "\(snapshot?.timeInRange != nil)",
                "\(snapshot?.hasDeviceStatus ?? false)", snapshot?.smartGuardText ?? "-",
                "\(snapshot?.glucoseStats != nil)",
                "\(snapshot?.sensorLife.rawValue ?? 0)", "\(snapshot?.infusionLife.rawValue ?? 0)",
                prefs.language.rawValue]
            .joined(separator: "|")
    }
    private var lastLayoutSignature = ""
    private lazy var measuringView = NSHostingView(rootView: AnyView(makePopover().content))

    private func resizePanel(force: Bool = false) {
        guard let button = item.button else { return }
        let signature = layoutSignature
        guard force || signature != lastLayoutSignature else { return }
        lastLayoutSignature = signature
        let available = button.window?.screen?.visibleFrame.height ?? 700
        measuringView.rootView = AnyView(makePopover().content)
        let height = min(ceil(measuringView.fittingSize.height), max(200, available - 24))
        let size = NSSize(width:430, height:height)
        guard abs(popover.contentSize.height - height) > 0.5 else { return }
        if let host = popover.contentViewController as? NSHostingController<CareLinkPopover> {
            host.rootView = makePopover(height: height)
            host.preferredContentSize = size
        } else {
            let host = NSHostingController(rootView: makePopover(height: height))
            host.preferredContentSize = size
            popover.contentViewController = host
        }
        popover.contentSize = size
        DispatchQueue.main.async { [weak self] in self?.positionPanel() }
    }

    func popoverDidShow(_ notification: Notification) { positionPanel() }

    private func positionPanel() {
        guard let button = item.button,
              let anchorWindow = button.window,
              let screen = anchorWindow.screen,
              let window = popover.contentViewController?.view.window else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // AppKit may adjust a popover on a short display. Keep its entire frame below the bar.
        let top = min(anchor.minY, screen.visibleFrame.maxY) - 4
        var frame = window.frame
        if frame.maxY > top {
            frame.origin.y = top - frame.height
            window.setFrame(frame, display: true)
        }
    }
    func applicationWillTerminate(_ notification: Notification) { store?.stop() }

    /// carelinkmenu://open (widget click) shows the panel; ignored before consent.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == SharedStore.openURL.scheme }), Consent.isAccepted, store != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }
}

@main
struct CareLinkMenubar {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

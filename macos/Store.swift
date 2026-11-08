import AppKit
import SwiftUI

@MainActor
final class CareLinkStore: ObservableObject {
    @Published var historyHours = 24
    @Published var snapshot: Snapshot?
    @Published var isRefreshing = false
    @Published var isSigningIn = false
    @Published var isSignedIn = false
    @Published var requiresLogin = false
    @Published var errorMessage: String?
    @Published var lastSuccess: Date?
    @Published var now = Date()
    @Published var nextRefresh: Date?
    @Published var accountName: String?
    var onChange: (() -> Void)?
    var loginAnchor: (() -> NSWindow)?
    private var gate = RefreshGate()
    private var alerts = CareLinkStore.restoredAlerts()
    private static let sensorLevelKey = "notifiedSensorLife", infusionLevelKey = "notifiedInfusionLife"
    /// Consumable levels already notified survive relaunches (otherwise every launch repeats them).
    private static func restoredAlerts() -> TechnicalAlerts {
        let defaults = UserDefaults.standard
        return TechnicalAlerts(sensorLevel: LifeLevel(rawValue: defaults.integer(forKey: sensorLevelKey)) ?? .normal,
                               infusionLevel: LifeLevel(rawValue: defaults.integer(forKey: infusionLevelKey)) ?? .normal)
    }
    private func saveAlertLevels() {
        UserDefaults.standard.set(alerts.sensorLevel.rawValue, forKey: Self.sensorLevelKey)
        UserDefaults.standard.set(alerts.infusionLevel.rawValue, forKey: Self.infusionLevelKey)
    }
    /// Technical alert sink (notifications live in the app layer, outside the checks).
    var onAlert: ((TechnicalAlerts.Alert) -> Void)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var work: Task<Void, Never>?
    private var generation = 0
    private var stopped = false
    private var suspended = false
    private let vault: TokenStorage
    private let api: NativeAPI
    private let browser = WebLogin()

    init(vault: TokenStorage = CredentialVault(), session: URLSession? = nil) {
        self.vault = vault
        self.api = NativeAPI(vault:vault, session:session)
    }
    var payloadShape: [String]? { api.lastShape }
    var stale: Bool { snapshot?.isStale(at:now) ?? true }
    var showTrendInMenuBar = true
    var statusTitle: String {
        guard let snapshot else { return isRefreshing || isSigningIn ? "CL …" : "CL —" }
        let suffix = snapshot.unit == "mmol/L" ? " mmol/L" : ""
        let warning = stale || errorMessage != nil ? " !" : ""
        let trend = showTrendInMenuBar ? " \(snapshot.trendSymbol)" : ""
        return "\(snapshot.glucoseText)\(suffix)\(trend)\(warning)"
    }
    func start() {
        do {
            let tokens = try vault.load()
            isSignedIn = tokens != nil
            accountName = tokens?.accountName
        }
        catch { errorMessage = CareLinkError.keychain.message }
        if isSignedIn { refresh() }
        timer = Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName:NSWorkspace.didWakeNotification, object:nil, queue:.main
        ) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func setRefreshInterval(_ seconds: TimeInterval) {
        gate.setInterval(seconds)
        if nextRefresh != nil { nextRefresh = gate.nextDue }
        onChange?()
    }
    func stop() {
        stopped = true
        cancelWork()
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
    private func cancelWork() {
        generation += 1
        work?.cancel(); work = nil
        browser.cancel()
        gate.finish()
        isRefreshing = false; isSigningIn = false
    }
    func tick() {
        guard !stopped else { return }
        now = Date()
        if gate.hasTimedOut(at:now) {
            cancelWork()
            errorMessage = tr("A consulta demorou demasiado. Tenta atualizar novamente.")
        } else if isSignedIn && !requiresLogin && !isSigningIn && !suspended {
            let age = snapshot?.sensorDate.map { now.timeIntervalSince($0) }
            if gate.isDue(at:now) || gate.staleRetryDue(readingAge:age, at:now) { refresh() }
        }
        if isSignedIn && !isSigningIn && !suspended {
            let age = snapshot?.sensorDate.map { now.timeIntervalSince($0) }
            let fetchedRecently = lastSuccess.map { now.timeIntervalSince($0) < 600 } ?? false
            for alert in alerts.evaluate(readingAge:age, sessionExpired:requiresLogin, fetchedRecently:fetchedRecently) {
                onAlert?(alert)
            }
            if let snapshot {
                let before = (alerts.sensorLevel, alerts.infusionLevel)
                for alert in alerts.evaluateLife(sensor:snapshot.sensorLife, sensorHours:snapshot.sensorHoursLeft,
                                                 infusion:snapshot.infusionLife,
                                                 infusionHours:snapshot.infusionTimeLeft.map { $0 / 60 }) {
                    onAlert?(alert)
                }
                if before != (alerts.sensorLevel, alerts.infusionLevel) { saveAlertLevels() }
            }
        }
        onChange?()
    }
    func signIn() {
        guard !stopped, !isSigningIn else { return }
        cancelWork()
        isSigningIn = true; errorMessage = nil
        let epoch = generation
        let anchor = loginAnchor?() ?? NSWindow()
        work = Task {
            do {
                let metadata = try await api.metadata()
                let state = try OAuthFlow.random(), verifier = try OAuthFlow.random()
                let callback = try await browser.authenticate(
                    url:OAuthFlow.authorizationURL(metadata:metadata,state:state,verifier:verifier),
                    redirect:metadata.redirect, anchor:anchor)
                let code = try OAuthFlow.code(from:callback,redirect:metadata.redirect,state:state)
                let tokens = try await api.exchange(code:code,verifier:verifier,metadata:metadata)
                try Task.checkCancellation()
                guard epoch == generation, !stopped else { return }
                try vault.save(tokens)
                accountName = tokens.accountName
                // Do not show the previous account's readings after an account change.
                snapshot = nil; lastSuccess = nil; alerts = Self.restoredAlerts()
                isSigningIn = false; isSignedIn = true; requiresLogin = false; suspended = false
                work = nil
                refresh()
            } catch {
                guard epoch == generation, !stopped else { return }
                isSigningIn = false; work = nil
                errorMessage = (error as? CareLinkError)?.message ?? CareLinkError.network.message
                onChange?()
            }
        }
        onChange?()
    }
    func cancelLogin() {
        cancelWork()
        errorMessage = tr("Início de sessão cancelado.")
        onChange?()
    }
    func logout() {
        cancelWork()
        alerts = TechnicalAlerts(); saveAlertLevels()
        snapshot = nil; lastSuccess = nil; nextRefresh = nil
        api.clearShape()
        do {
            try vault.clear()
            // Only suspend once the session is really gone; otherwise refresh stays usable.
            suspended = true
            isSignedIn = false; requiresLogin = false; errorMessage = nil; accountName = nil
        } catch {
            errorMessage = tr("Não foi possível remover a sessão do Porta-chaves. Tenta Terminar sessão novamente.")
            isSignedIn = true
        }
        onChange?()
    }
    func refresh() {
        guard !stopped, isSignedIn, !isSigningIn, !requiresLogin, !suspended, gate.begin(at:Date()) else { return }
        isRefreshing = true
        nextRefresh = gate.nextDue
        let epoch = generation
        work = Task {
            do {
                let fresh = try await api.fetch()
                try Task.checkCancellation()
                guard epoch == generation, !stopped else { return }
                snapshot = fresh; lastSuccess = Date(); errorMessage = nil
            } catch {
                guard epoch == generation, !stopped else { return }
                errorMessage = (error as? CareLinkError)?.message ?? CareLinkError.network.message
                if case CareLinkError.authentication = error { requiresLogin = true; nextRefresh = nil }
                else { gate.retrySoon(at:Date()); nextRefresh = gate.nextDue }
            }
            guard epoch == generation, !stopped else { return }
            gate.finish(); isRefreshing = false; work = nil; now = Date()
            onChange?()
        }
        onChange?()
    }
}

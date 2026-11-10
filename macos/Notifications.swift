import Foundation
import UserNotifications

/// Local macOS notifications for technical failures and new app versions (never glucose values or alarms).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the clicked notification's identifier.
    var onOpen: ((String) -> Void)?
    static let updateIdentifier = "update-available"
    private let center = UNUserNotificationCenter.current()

    func setUp(requestPermission: Bool) {
        center.delegate = self
        if requestPermission { self.requestPermission() }
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ alert: TechnicalAlerts.Alert) {
        let content = UNMutableNotificationContent()
        let identifier: String
        switch alert {
        case .sessionExpired:
            identifier = "session-expired"
            content.title = tr("CareLink: sessão expirada")
            content.body = tr("Volta a entrar no CareLink para continuar a ver os dados.")
        case .noRecentData(let minutes):
            identifier = "no-recent-data"
            content.title = tr("CareLink: sem leituras novas")
            content.body = tr("A última leitura tem %@min. Verifica o telemóvel, a bomba e o sensor.", "\(minutes)")
        case .consumableEnding(let item, let level, let hours):
            let critical = level == .critical
            let left = hours.map { Snapshot.compactDuration(hours: $0) }
            switch item {
            case .sensor:
                identifier = "sensor-ending"
                content.title = tr(critical ? "CareLink: o sensor está a terminar" : "CareLink: trocar sensor em breve")
                content.body = left.map { tr("Faltam %@ para o fim do sensor.", $0) } ?? tr("Trocar sensor em breve")
            case .infusion:
                identifier = "infusion-ending"
                content.title = tr(critical ? "CareLink: o conjunto está a terminar" : "CareLink: trocar conjunto em breve")
                content.body = left.map { tr("Faltam %@ para trocar o conjunto de infusão.", $0) }
                    ?? tr("Está na altura de trocar o conjunto de infusão")
            }
        }
        content.sound = .default
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// A new version found by a scheduled check; clicking it opens the update window.
    func postUpdate(version: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("CareLink Menubar: nova versão disponível")
        content.body = tr("A versão %@ está disponível. Clica para ver as novidades e atualizar.", version)
        center.add(UNNotificationRequest(identifier: Self.updateIdentifier, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        Task { @MainActor in self.onOpen?(identifier) }
        completionHandler()
    }
}

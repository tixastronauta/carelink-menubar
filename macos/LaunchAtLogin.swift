import AppKit
import ServiceManagement

/// Observable wrapper around the macOS login item registration for this app.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var message: String?
    private let service = SMAppService.mainApp

    init() { reload() }

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    func reload() { status = service.status }

    func set(_ enabled: Bool) {
        message = nil
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            message = tr("Não foi possível alterar o arranque automático. Confirma em Definições do Sistema → Geral → Itens de início de sessão.")
        }
        reload()
        if enabled && requiresApproval { openSettings() }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// True when macOS opened the app as a login item rather than the user opening it.
    static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}

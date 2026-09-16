import Observation
import ServiceManagement

/// "Launch at login" via `SMAppService` (no helper app, no LaunchAgent plist).
@MainActor
@Observable
final class LoginItemService {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?

    init() {
        refresh()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLog.app.error("Updating login item failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

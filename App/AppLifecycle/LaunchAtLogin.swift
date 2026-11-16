import Combine
import OSLog
import ServiceManagement

/// Launch at login via `SMAppService.mainApp` (macOS 13+, no helper app).
///
/// The toggle always reflects the *system* state, never a cached flag, so
/// turning it off in System Settings › General › Login Items is respected
/// and the app never re-registers itself. Launching at login only starts
/// the app: keeping the Mac awake always needs a user action.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.app", category: "login-item")

    private init() { refresh() }

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

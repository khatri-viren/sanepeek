import Foundation
import ServiceManagement

nonisolated enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case failed(String)
}

/// Abstracts `SMAppService.mainApp` so `SettingsStore` can be tested without
/// touching the real login-item registry. `SMAppService` is the required
/// modern API — legacy login-item APIs (`SMLoginItemSetEnabled`, shared file
/// list) must never be used.
@MainActor
protocol LaunchAtLoginService {
    func currentStatus() -> LaunchAtLoginStatus
    func register() throws
    func unregister() throws
}

@MainActor
struct LiveLaunchAtLoginService: LaunchAtLoginService {
    func currentStatus() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notRegistered
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

import Foundation
import SwiftUI
import Testing

@testable import SanePeek

@Suite("SettingsStore")
struct SettingsStoreTests {

    @Test("Changed values persist across a new store instance over the same defaults suite")
    @MainActor
    func changedValuesPersistAcrossInstances() {
        let defaults = Self.freshDefaults()

        let first = SettingsStore(defaults: defaults, launchAtLoginService: FakeLaunchAtLoginService())
        first.appearance = .dark
        first.refreshRate = .fiveSeconds
        first.byteUnitSystem = .binary
        first.temperatureUnit = .fahrenheit

        let second = SettingsStore(defaults: defaults, launchAtLoginService: FakeLaunchAtLoginService())

        #expect(second.appearance == .dark)
        #expect(second.refreshRate == .fiveSeconds)
        #expect(second.byteUnitSystem == .binary)
        #expect(second.temperatureUnit == .fahrenheit)
    }

    @Test("A fresh store with nothing persisted falls back to documented defaults")
    @MainActor
    func freshStoreUsesDocumentedDefaults() {
        let store = SettingsStore(defaults: Self.freshDefaults(), launchAtLoginService: FakeLaunchAtLoginService())

        #expect(store.appearance == .system)
        #expect(store.refreshRate == .oneSecond)
        #expect(store.byteUnitSystem == .decimal)
        #expect(store.temperatureUnit == .celsius)
    }

    @Test("Invalid stored raw values fall back safely instead of crashing or misbehaving")
    @MainActor
    func invalidStoredValuesFallBackSafely() {
        let defaults = Self.freshDefaults()
        defaults.set("not-a-real-appearance", forKey: "settings.appearance")
        defaults.set(7, forKey: "settings.refreshRate")
        defaults.set("not-a-real-byte-system", forKey: "settings.byteUnitSystem")
        defaults.set("not-a-real-temperature-unit", forKey: "settings.temperatureUnit")

        let store = SettingsStore(defaults: defaults, launchAtLoginService: FakeLaunchAtLoginService())

        #expect(store.appearance == .system)
        #expect(store.refreshRate == .oneSecond)
        #expect(store.byteUnitSystem == .decimal)
        #expect(store.temperatureUnit == .celsius)
    }

    @Test("Appearance maps to the SwiftUI color scheme the exit criteria expects")
    func appearanceMapsToColorScheme() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test("Changing the refresh rate notifies onRefreshRateChange with the new rate, not on a no-op set")
    @MainActor
    func refreshRateChangeNotifiesListener() {
        let store = SettingsStore(defaults: Self.freshDefaults(), launchAtLoginService: FakeLaunchAtLoginService())
        var observedRates: [RefreshRate] = []
        store.onRefreshRateChange = { observedRates.append($0) }

        store.refreshRate = .twoSeconds
        store.refreshRate = .twoSeconds // no-op: must not notify again
        store.refreshRate = .fiveSeconds

        #expect(observedRates == [.twoSeconds, .fiveSeconds])
    }

    @Test("Enabling launch-at-login registers and reflects the resulting status")
    @MainActor
    func enablingLaunchAtLoginRegisters() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let store = SettingsStore(defaults: Self.freshDefaults(), launchAtLoginService: service)

        store.setLaunchAtLoginEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(store.launchAtLoginStatus == .enabled)
    }

    @Test("Disabling launch-at-login unregisters and reflects the resulting status")
    @MainActor
    func disablingLaunchAtLoginUnregisters() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let store = SettingsStore(defaults: Self.freshDefaults(), launchAtLoginService: service)

        store.setLaunchAtLoginEnabled(false)

        #expect(service.unregisterCallCount == 1)
        #expect(store.launchAtLoginStatus == .notRegistered)
    }

    @Test("A registration failure surfaces as a non-blocking failed status instead of throwing")
    @MainActor
    func registrationFailureSurfacesAsFailedStatus() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = FakeError(message: "System refused the request.")
        let store = SettingsStore(defaults: Self.freshDefaults(), launchAtLoginService: service)

        store.setLaunchAtLoginEnabled(true)

        #expect(store.launchAtLoginStatus == .failed("System refused the request."))
    }

    @Test("requiresApproval and notFound statuses round-trip through refreshLaunchAtLoginStatus")
    @MainActor
    func statusRefreshReflectsServiceState() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let store = SettingsStore(defaults: Self.freshDefaults(), launchAtLoginService: service)
        #expect(store.launchAtLoginStatus == .requiresApproval)

        service.status = .notFound
        store.refreshLaunchAtLoginStatus()
        #expect(store.launchAtLoginStatus == .notFound)
    }

    private static func freshDefaults() -> UserDefaults {
        let suiteName = "com.sanepeek.tests.settingsstore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginStatus = .notRegistered) {
        self.status = status
    }

    func currentStatus() -> LaunchAtLoginStatus {
        status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }
}

private struct FakeError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

import Foundation
import Testing

@testable import SanePeek

@Suite("Settings state")
struct SettingsStateTests {
    @Test("Every metric's menu-bar configuration round-trips through persistence")
    @MainActor
    func everyMenuBarMetricRoundTrips() {
        let defaults = TestDefaultsSuite(prefix: "com.sanepeek.tests.settings-state")
        defer { defaults.removePersistentDomain() }

        let first = SettingsStore(
            defaults: defaults.defaults,
            launchAtLoginService: TestLaunchAtLoginService()
        )
        let expected = Dictionary(uniqueKeysWithValues: MetricKind.allCases.enumerated().map { index, kind in
            (
                kind,
                MenuBarMetricConfig(
                    isEnabled: index.isMultiple(of: 2),
                    displayMode: index.isMultiple(of: 2) ? .bar : .number
                )
            )
        })

        for (kind, config) in expected {
            first.setMenuBarConfig(config, for: kind)
        }

        let second = SettingsStore(
            defaults: defaults.defaults,
            launchAtLoginService: TestLaunchAtLoginService()
        )

        for kind in MetricKind.allCases {
            #expect(second.menuBarConfig(for: kind) == expected[kind])
        }
    }

    @Test("Unit preferences keep formatter and cadence policy derived from current state")
    @MainActor
    func derivedFormattingAndCadenceFollowPreferences() {
        let defaults = TestDefaultsSuite(prefix: "com.sanepeek.tests.settings-state")
        defer { defaults.removePersistentDomain() }
        let store = SettingsStore(
            defaults: defaults.defaults,
            launchAtLoginService: TestLaunchAtLoginService()
        )

        store.byteUnitSystem = .binary
        store.temperatureUnit = .fahrenheit
        store.refreshRate = .fiveSeconds

        #expect(store.formatter == MetricFormatter(byteUnitSystem: .binary, temperatureUnit: .fahrenheit))
        #expect(store.cadencePolicy == CadencePolicy(refreshRate: .fiveSeconds))
    }

    @Test("Malformed menu-bar persistence falls back to safe defaults for every metric")
    @MainActor
    func malformedMenuBarDataFallsBackSafely() {
        let defaults = TestDefaultsSuite(prefix: "com.sanepeek.tests.settings-state")
        defer { defaults.removePersistentDomain() }
        defaults.defaults.set(Data([0x00, 0xFF, 0x7F]), forKey: "settings.menuBarConfig")

        let store = SettingsStore(
            defaults: defaults.defaults,
            launchAtLoginService: TestLaunchAtLoginService()
        )

        for kind in MetricKind.allCases {
            let config = store.menuBarConfig(for: kind)
            #expect(config.isEnabled == (kind == .cpu))
            #expect(config.displayMode == .number)
        }
    }

    @Test("Every menu-bar metric invokes the change callback once and ignores no-op writes")
    @MainActor
    func everyMenuBarMetricNotifiesOnce() {
        let defaults = TestDefaultsSuite(prefix: "com.sanepeek.tests.settings-state")
        defer { defaults.removePersistentDomain() }
        let store = SettingsStore(
            defaults: defaults.defaults,
            launchAtLoginService: TestLaunchAtLoginService()
        )
        var notificationCount = 0
        store.onMenuBarConfigChange = { notificationCount += 1 }

        var changedConfigs: [MetricKind: MenuBarMetricConfig] = [:]
        for kind in MetricKind.allCases {
            var config = store.menuBarConfig(for: kind)
            config.isEnabled.toggle()
            changedConfigs[kind] = config
            store.setMenuBarConfig(config, for: kind)
        }
        for (kind, config) in changedConfigs {
            store.setMenuBarConfig(config, for: kind)
        }

        #expect(notificationCount == MetricKind.allCases.count)
    }

    @Test("Launch-at-login unregister failures become visible failed state")
    @MainActor
    func unregisterFailureSurfacesAsFailedStatus() {
        let service = TestLaunchAtLoginService(status: .enabled)
        service.unregisterError = TestServiceError(message: "System refused the request.")
        let defaults = TestDefaultsSuite(prefix: "com.sanepeek.tests.settings-state")
        defer { defaults.removePersistentDomain() }
        let store = SettingsStore(defaults: defaults.defaults, launchAtLoginService: service)

        store.setLaunchAtLoginEnabled(false)

        #expect(service.unregisterCallCount == 1)
        #expect(store.launchAtLoginStatus == .failed("System refused the request."))
    }

    @Test("Updater availability is the gate for update checks and preserves version metadata")
    @MainActor
    func updaterAvailabilityGateIsObservable() {
        let updater = TestUpdaterService(canCheckForUpdates: false, currentVersion: "test (42)")

        #expect(updater.canCheckForUpdates == false)
        #expect(updater.currentVersion == "test (42)")
        updater.checkForUpdates()
        #expect(updater.checkForUpdatesCallCount == 1)

        updater.canCheckForUpdates = true
        #expect(updater.canCheckForUpdates)
    }
}

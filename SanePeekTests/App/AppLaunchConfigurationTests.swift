import Foundation
import Testing

@testable import SanePeek

@Suite("App launch configuration")
struct AppLaunchConfigurationTests {
    @Test("UI launch arguments select fixture, isolated settings, and menu-bar seed")
    @MainActor
    func uiLaunchArgumentsSelectDeterministicConfiguration() {
        let dependencies = AppDependencies.forLaunch(arguments: [
            "SanePeek",
            "-uiTestFixture", "mixedFailure",
            "-uiTestSettingsSuite", "com.sanepeek.uitests.example",
            "-uiTestMenuBar", "cpu:number,memory:bar,temperature:number"
        ])

        #expect(dependencies.runtime == .preview)
        #expect(dependencies.fixtureSnapshot == MetricFixtures.mixedFailure())
        #expect(dependencies.settingsDefaultsSuiteName == "com.sanepeek.uitests.example")
        #expect(dependencies.menuBarSeed == [
            .cpu: MenuBarMetricConfig(isEnabled: true, displayMode: .number),
            .memory: MenuBarMetricConfig(isEnabled: true, displayMode: .bar),
            .temperature: MenuBarMetricConfig(isEnabled: true, displayMode: .number)
        ])
    }

    @Test("Malformed menu-bar seed falls back to persisted settings instead of partially applying")
    @MainActor
    func malformedMenuBarSeedIsIgnored() {
        let dependencies = AppDependencies.forLaunch(arguments: [
            "SanePeek",
            "-uiTestFixture", "baseline",
            "-uiTestMenuBar", "cpu:number,not-a-kind:bar"
        ])

        #expect(dependencies.menuBarSeed == nil)
    }

    @Test("AppState applies the menu-bar seed before consumers observe settings")
    @MainActor
    func appStateAppliesMenuBarSeedDeterministically() {
        let defaults = TestDefaultsSuite(prefix: "com.sanepeek.tests.app-launch")
        defer { defaults.removePersistentDomain() }
        let dependencies = AppDependencies(
            runtime: .preview,
            fixtureSnapshot: MetricFixtures.baseline(),
            settingsDefaultsSuiteName: defaults.name,
            menuBarSeed: [
                .cpu: MenuBarMetricConfig(isEnabled: true, displayMode: .number),
                .memory: MenuBarMetricConfig(isEnabled: true, displayMode: .bar)
            ]
        )

        let appState = AppState(dependencies: dependencies)

        #expect(appState.settingsStore.menuBarConfig(for: .cpu) == MenuBarMetricConfig(isEnabled: true, displayMode: .number))
        #expect(appState.settingsStore.menuBarConfig(for: .memory) == MenuBarMetricConfig(isEnabled: true, displayMode: .bar))
        for kind in MetricKind.allCases where kind != .cpu && kind != .memory {
            #expect(appState.settingsStore.menuBarConfig(for: kind) == MenuBarMetricConfig(isEnabled: false, displayMode: .number))
        }
    }
}

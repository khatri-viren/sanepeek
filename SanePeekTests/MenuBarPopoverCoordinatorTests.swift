import Foundation
import Testing

@testable import SanePeek

@Suite("Menu bar monitor window hand-off")
struct MenuBarPopoverCoordinatorTests {
    @Test("A rapid hand-off immediately targets the latest clicked metric")
    func rapidHandoffUsesTheLastClick() {
        var coordinator = MenuBarPopoverCoordinator()

        #expect(coordinator.select(.cpu, panelIsVisible: false) == .show(.cpu))
        #expect(coordinator.select(.memory, panelIsVisible: true) == .handoff(from: .cpu, to: .memory))
        #expect(coordinator.select(.temperature, panelIsVisible: true) == .handoff(from: .memory, to: .temperature))
        #expect(coordinator.activeKind == .temperature)
    }

    @Test("Selecting the active item closes without reopening it")
    func selectingActiveItemClosesIt() {
        var coordinator = MenuBarPopoverCoordinator()

        #expect(coordinator.select(.cpu, panelIsVisible: false) == .show(.cpu))
        #expect(coordinator.select(.cpu, panelIsVisible: true) == .dismiss(.cpu))
        #expect(coordinator.activeKind == nil)
    }

    @Test("Enabling multiple metrics installs all of their status items")
    @MainActor
    func enablingMultipleMetricsInstallsEveryStatusItem() async {
        let suiteName = "com.sanepeek.tests.menu-bar-controller.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let appState = AppState(
            dependencies: AppDependencies(
                runtime: .preview,
                fixtureSnapshot: MetricFixtures.baseline(),
                settingsDefaultsSuiteName: suiteName
            )
        )
        let controller = MenuBarPopoverController()
        defer {
            controller.tearDown()
            defaults.removePersistentDomain(forName: suiteName)
        }
        controller.configure(appState: appState)

        #expect(controller.installedStatusItemKinds == [.cpu])
        #expect(controller.statusItemAutosaveNames[.cpu] == "com.sanepeek.status-item.cpu")
        appState.settingsStore.setMenuBarConfig(
            MenuBarMetricConfig(isEnabled: true, displayMode: .number),
            for: .memory
        )
        appState.settingsStore.setMenuBarConfig(
            MenuBarMetricConfig(isEnabled: true, displayMode: .bar),
            for: .temperature
        )
        let expectedKinds: Set<MetricKind> = [.cpu, .memory, .temperature]
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while controller.installedStatusItemKinds != expectedKinds,
              DispatchTime.now().uptimeNanoseconds < deadline {
            await Task.yield()
        }

        #expect(controller.installedStatusItemKinds == expectedKinds)
        #expect(controller.statusItemAutosaveNames == [
            .cpu: "com.sanepeek.status-item.cpu",
            .memory: "com.sanepeek.status-item.memory",
            .temperature: "com.sanepeek.status-item.temperature"
        ])
    }
}

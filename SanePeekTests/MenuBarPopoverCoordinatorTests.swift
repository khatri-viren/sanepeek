import Foundation
import Testing

@testable import SanePeek

@Suite("Menu bar popover hand-off")
struct MenuBarPopoverCoordinatorTests {
    @Test("A rapid hand-off presents only the last clicked metric")
    func rapidHandoffUsesTheLastClick() {
        var coordinator = MenuBarPopoverCoordinator()

        #expect(coordinator.select(.cpu, popoverIsPresented: false) == .present(.cpu))
        #expect(coordinator.select(.memory, popoverIsPresented: true) == .dismiss)
        #expect(coordinator.select(.temperature, popoverIsPresented: true) == .none)
        #expect(coordinator.popoverDidClose() == .present(.temperature))
        #expect(coordinator.activeKind == .temperature)
    }

    @Test("Selecting the active item closes without reopening it")
    func selectingActiveItemClosesIt() {
        var coordinator = MenuBarPopoverCoordinator()

        #expect(coordinator.select(.cpu, popoverIsPresented: false) == .present(.cpu))
        #expect(coordinator.select(.cpu, popoverIsPresented: true) == .dismiss)
        #expect(coordinator.popoverDidClose() == .none)
        #expect(coordinator.activeKind == nil)
    }

    @Test("Enabling multiple metrics installs all of their status items")
    @MainActor
    func enablingMultipleMetricsInstallsEveryStatusItem() async {
        let suiteName = "com.sanepeek.tests.menu-bar-controller.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            dependencies: AppDependencies(
                runtime: .preview,
                fixtureSnapshot: MetricFixtures.dashboard(),
                settingsDefaultsSuiteName: suiteName
            )
        )
        let controller = MenuBarPopoverController()
        controller.configure(appState: appState)

        #expect(controller.installedStatusItemKinds == [.cpu])
        #expect(controller.statusItemAutosaveNames[.cpu] == "com.sanepeek.status-item.cpu")
        // The system's popover animation is always off; open/close motion is a manual opacity
        // fade on the content view instead (see `MenuBarPopoverController.transitionDuration`).
        #expect(!controller.popoverAnimates)

        appState.settingsStore.setMenuBarConfig(
            MenuBarMetricConfig(isEnabled: true, displayMode: .number),
            for: .memory
        )
        appState.settingsStore.setMenuBarConfig(
            MenuBarMetricConfig(isEnabled: true, displayMode: .bar),
            for: .temperature
        )
        await Task.yield()
        await Task.yield()

        #expect(controller.installedStatusItemKinds == [.cpu, .memory, .temperature])
        #expect(controller.statusItemAutosaveNames == [
            .cpu: "com.sanepeek.status-item.cpu",
            .memory: "com.sanepeek.status-item.memory",
            .temperature: "com.sanepeek.status-item.temperature"
        ])
    }
}

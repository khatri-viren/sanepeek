import Foundation
import CoreGraphics
import Testing

@testable import SanePeek

@MainActor
@Suite("Menu bar popover controller")
struct MenuBarPopoverControllerTests {
    @Test("Status-item selection shows, hands off, and dismisses one shared monitor window")
    func statusItemSelectionUsesSharedWindowLifecycle() {
        let defaults = isolatedDefaults()
        let appState = AppState(
            dependencies: AppDependencies(
                runtime: .preview,
                fixtureSnapshot: MetricFixtures.baseline(),
                settingsDefaultsSuiteName: defaults.name
            )
        )
        appState.settingsStore.setMenuBarConfig(
            MenuBarMetricConfig(isEnabled: true, displayMode: .number),
            for: .memory
        )

        let controller = MenuBarPopoverController()
        defer {
            controller.tearDown()
            defaults.removePersistentDomain()
        }
        controller.configure(appState: appState)

        #expect(controller.selectStatusItem(.cpu))
        #expect(controller.isMonitorWindowVisible)
        #expect(controller.selectedMetricKind == .cpu)
        #expect(controller.monitorWindowFrame?.width == 560)
        #expect((controller.monitorWindowFrame?.height ?? 0) > 0)
        #expect(appState.isPopupVisible(kind: .cpu))

        #expect(controller.selectStatusItem(.memory))
        #expect(controller.isMonitorWindowVisible)
        #expect(controller.selectedMetricKind == .memory)
        #expect(!appState.isPopupVisible(kind: .cpu))
        #expect(appState.isPopupVisible(kind: .memory))

        #expect(controller.selectStatusItem(.memory))
        #expect(!controller.isMonitorWindowVisible)
        #expect(controller.selectedMetricKind == .memory)
        #expect(!appState.isPopupVisible(kind: .memory))
    }

    @Test("Status-item reconfiguration and teardown do not duplicate or leak items")
    func statusItemReconfigurationCleansUpAppKitOwnership() async {
        let defaults = isolatedDefaults()
        let appState = AppState(
            dependencies: AppDependencies(
                runtime: .preview,
                fixtureSnapshot: MetricFixtures.baseline(),
                settingsDefaultsSuiteName: defaults.name
            )
        )
        let controller = MenuBarPopoverController()
        defer {
            controller.tearDown()
            defaults.removePersistentDomain()
        }

        controller.configure(appState: appState)
        #expect(controller.installedStatusItemKinds == [.cpu])
        let initialNames = controller.statusItemAutosaveNames

        controller.configure(appState: appState)
        #expect(controller.installedStatusItemKinds == [.cpu])
        #expect(controller.statusItemAutosaveNames == initialNames)

        appState.settingsStore.setMenuBarConfig(
            MenuBarMetricConfig(isEnabled: true, displayMode: .bar),
            for: .memory
        )
        await waitUntil { controller.installedStatusItemKinds == [.cpu, .memory] }

        appState.settingsStore.setMenuBarConfig(
            MenuBarMetricConfig(isEnabled: false, displayMode: .number),
            for: .cpu
        )
        await waitUntil { controller.installedStatusItemKinds == [.memory] }
        #expect(!controller.selectStatusItem(.cpu))

        #expect(controller.selectStatusItem(.memory))
        controller.tearDown()

        #expect(controller.installedStatusItemKinds.isEmpty)
        #expect(controller.statusItemAutosaveNames.isEmpty)
        #expect(!controller.isMonitorWindowVisible)
        #expect(!appState.isPopupVisible(kind: .memory))
    }

    private func isolatedDefaults() -> TestDefaultsSuite {
        TestDefaultsSuite(prefix: "com.sanepeek.tests.menu-bar-controller")
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition(), clock.now < deadline {
            await Task.yield()
        }
        #expect(condition())
    }
}

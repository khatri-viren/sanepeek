import Foundation
import Testing

@testable import SanePeek

/// Covers the shared popover lifecycle used to widen polling while a user is looking at a
/// menu-bar detail view.
@MainActor
@Suite("AppState popup tracking")
struct AppStatePopupTests {
    @Test("No popup is visible before any opens")
    func startsWithNoVisiblePopup() {
        #expect(!makeAppState().isPopupVisible(kind: .cpu))
    }

    @Test("Opening a popup records its metric")
    func openingPopupRecordsItsMetric() {
        let appState = makeAppState()
        _ = appState.popupDidAppear(kind: .memory)
        #expect(appState.isPopupVisible(kind: .memory))
    }

    @Test("Closing a popup clears its visible state")
    func closingPopupClearsItsVisibleState() {
        let appState = makeAppState()
        let sessionID = appState.popupDidAppear(kind: .memory)
        appState.popupDidDisappear(kind: .memory, sessionID: sessionID)
        #expect(!appState.isPopupVisible(kind: .memory))
    }

    @Test("A delayed close from an outgoing metric does not clear its replacement")
    func delayedCloseFromOutgoingMetricDoesNotClearReplacement() {
        let appState = makeAppState()
        let cpuSessionID = appState.popupDidAppear(kind: .cpu)
        _ = appState.popupDidAppear(kind: .memory)
        appState.popupDidDisappear(kind: .cpu, sessionID: cpuSessionID)

        #expect(appState.isPopupVisible(kind: .memory))
    }

    @Test("A stale close from an earlier session does not clear a re-opened popup")
    func staleCloseFromEarlierSessionDoesNotClearCurrentPopup() {
        let appState = makeAppState()
        let firstCPUSessionID = appState.popupDidAppear(kind: .cpu)
        _ = appState.popupDidAppear(kind: .memory)
        let currentCPUSessionID = appState.popupDidAppear(kind: .cpu)

        appState.popupDidDisappear(kind: .cpu, sessionID: firstCPUSessionID)
        #expect(appState.isPopupVisible(kind: .cpu))

        appState.popupDidDisappear(kind: .cpu, sessionID: currentCPUSessionID)
        #expect(!appState.isPopupVisible(kind: .cpu))
    }

    /// `.preview` carries no `MetricsEngine`, so `recomputePollingState` returns early and
    /// these assertions exercise the visibility bookkeeping alone. The defaults suite is
    /// per-test so nothing here touches the real app's settings.
    private func makeAppState() -> AppState {
        AppState(
            dependencies: AppDependencies(
                runtime: .preview,
                fixtureSnapshot: MetricFixtures.baseline(),
                settingsDefaultsSuiteName: "com.sanepeek.tests.appstatepopup.\(UUID().uuidString)"
            )
        )
    }
}

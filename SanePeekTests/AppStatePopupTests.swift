import Foundation
import Testing

@testable import SanePeek

/// Covers `AppState.frontmostPopupKind`, which is how one menu bar item's popup tells the
/// others to close. Every enabled metric declares its own `MenuBarExtra` and therefore its own
/// popup window, and macOS does not dismiss one when a different item is clicked — so without
/// this bookkeeping every enabled metric could have a copy on screen at once.
@MainActor
@Suite("AppState popup tracking")
struct AppStatePopupTests {
    @Test("No popup is frontmost before any opens")
    func startsWithNoFrontmostPopup() {
        #expect(makeAppState().frontmostPopupKind == nil)
    }

    @Test("Opening a popup makes its own metric frontmost")
    func openingPopupClaimsFrontmost() {
        let appState = makeAppState()
        appState.handlePopupVisibilityChange(isVisible: true, kind: .memory)
        #expect(appState.frontmostPopupKind == .memory)
    }

    @Test("Closing the frontmost popup clears it")
    func closingFrontmostPopupClearsIt() {
        let appState = makeAppState()
        appState.handlePopupVisibilityChange(isVisible: true, kind: .memory)
        appState.handlePopupVisibilityChange(isVisible: false, kind: .memory)
        #expect(appState.frontmostPopupKind == nil)
    }

    /// The ordering that makes the hand-off work. Clicking a second menu bar item shows its
    /// popup *before* the first one finishes dismissing, so the outgoing popup's
    /// `onDisappear` lands last. If that late callback cleared `frontmostPopupKind`
    /// unconditionally, the incoming popup would immediately look like nothing is frontmost.
    @Test("A popup closing after another has taken over does not clear the new one")
    func lateCloseFromOutgoingPopupDoesNotClearTheIncomingOne() {
        let appState = makeAppState()
        appState.handlePopupVisibilityChange(isVisible: true, kind: .cpu)
        appState.handlePopupVisibilityChange(isVisible: true, kind: .memory)
        appState.handlePopupVisibilityChange(isVisible: false, kind: .cpu)

        #expect(appState.frontmostPopupKind == .memory)
    }

    /// `.preview` carries no `MetricsEngine`, so `recomputePollingState` returns early and
    /// these assertions exercise the visibility bookkeeping alone. The defaults suite is
    /// per-test so nothing here touches the real app's settings.
    private func makeAppState() -> AppState {
        AppState(
            dependencies: AppDependencies(
                runtime: .preview,
                fixtureSnapshot: MetricFixtures.dashboard(),
                settingsDefaultsSuiteName: "com.sanepeek.tests.appstatepopup.\(UUID().uuidString)"
            )
        )
    }
}

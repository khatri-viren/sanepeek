//
//  SanePeekUITests.swift
//  SanePeekUITests
//

import XCTest

@MainActor
final class SanePeekUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDashboardLaunchesWithStableEntryPoints() throws {
        let app = XCUIApplication()
        app.launch()

        let dashboard = app.descendants(matching: .any)["dashboard.root"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.settings"].exists)
    }

    func testAllSixCardsAppearForTheBaselineFixture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture", "dashboard"]
        app.launch()

        for kind in ["cpu", "memory", "storage", "network", "battery", "gpu"] {
            let card = app.descendants(matching: .any)["dashboard.card.\(kind)"]
            XCTAssertTrue(card.waitForExistence(timeout: 5), "Expected dashboard.card.\(kind) to exist")
        }
    }

    func testGPUCardHidesWhenUnsupportedWhileSiblingsStayVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture", "gpuUnsupported"]
        app.launch()

        let cpuCard = app.descendants(matching: .any)["dashboard.card.cpu"]
        XCTAssertTrue(cpuCard.waitForExistence(timeout: 5))

        for kind in ["memory", "storage", "network", "battery"] {
            XCTAssertTrue(app.descendants(matching: .any)["dashboard.card.\(kind)"].exists)
        }
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.card.gpu"].exists)
    }

    /// `MetricCardMappingTests` already proves each card renders the right
    /// content for a given snapshot state; on macOS, SwiftUI's merged
    /// `.accessibilityElement(children: .ignore)` card doesn't surface
    /// `accessibilityValue` through XCUITest's `value` attribute for a plain
    /// group element, so this UI test instead proves the composition-level
    /// behavior the mapping tests can't: a mix of healthy and failed metrics
    /// renders every card side by side rather than a failure hiding siblings
    /// (as only the GPU card is ever allowed to do).
    func testCardSpecificFailureStatesCoexistWithHealthyCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture", "mixedFailure"]
        app.launch()

        for kind in ["cpu", "memory", "storage", "network", "battery", "gpu"] {
            let card = app.descendants(matching: .any)["dashboard.card.\(kind)"]
            XCTAssertTrue(card.waitForExistence(timeout: 5), "Expected dashboard.card.\(kind) to exist alongside the failed cards")
        }
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

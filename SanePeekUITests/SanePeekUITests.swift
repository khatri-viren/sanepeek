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

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

//
//  SanePeekUITestsLaunchTests.swift
//  SanePeekUITests
//

import XCTest

@MainActor
final class SanePeekUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsDashboardRoot() throws {
        let app = XCUIApplication()
        app.launch()

        let dashboard = app.descendants(matching: .any)["dashboard.root"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

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

    func testLaunchStaysSilentWithoutFullWindow() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.windows.count, 0)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Silent launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

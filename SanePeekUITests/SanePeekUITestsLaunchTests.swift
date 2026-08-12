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
        let harness = SanePeekUITestHarness()
        defer { harness.cleanup() }
        harness.launch()

        XCTAssertEqual(harness.app.windows.count, 0)

        let attachment = XCTAttachment(screenshot: harness.app.screenshot())
        attachment.name = "Silent launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

//
//  SettingsJourneyUITests.swift
//  SanePeekUITests
//

import XCTest

@MainActor
final class SettingsJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSettingsExposesEveryMenuBarMetricControlAndAccessibilityContract() throws {
        let harness = SanePeekUITestHarness()
        defer { harness.cleanup() }
        harness.launch()
        harness.openSettings()

        XCTAssertTrue(harness.element("settings.root").waitForExistence(timeout: 10))
        for kind in ["cpu", "memory", "storage", "network", "battery", "gpu", "temperature"] {
            XCTAssertTrue(harness.element("settings.menuBar.\(kind).enabled").exists)
            XCTAssertTrue(harness.element("settings.menuBar.\(kind).mode").exists)
        }
        XCTAssertTrue(harness.element("settings.checkForUpdates").exists)
    }

    func testMenuBarPreferencePersistsWhenTheFixtureSeedIsRemovedOnRelaunch() throws {
        let harness = SanePeekUITestHarness()
        defer { harness.cleanup() }
        harness.launch()
        harness.openSettings()

        let memoryEnabled = harness.element("settings.menuBar.memory.enabled")
        let memoryMode = harness.element("settings.menuBar.memory.mode")
        XCTAssertTrue(memoryEnabled.waitForExistence(timeout: 10))
        XCTAssertEqual(memoryEnabled.value as? Int, 0)

        memoryEnabled.click()
        XCTAssertTrue(XCTWaiter.wait(for: [valueExpectation(memoryEnabled, equals: 1)], timeout: 5) == .completed)

        memoryMode.click()
        let barOption = harness.app.descendants(matching: .any)["Bar"]
        XCTAssertTrue(barOption.waitForExistence(timeout: 5))
        barOption.click()

        harness.relaunch()
        harness.openSettings()

        let reopenedEnabled = harness.element("settings.menuBar.memory.enabled")
        let reopenedMode = harness.element("settings.menuBar.memory.mode")
        XCTAssertTrue(reopenedEnabled.waitForExistence(timeout: 10))
        XCTAssertEqual(reopenedEnabled.value as? Int, 1)
        XCTAssertEqual(reopenedMode.value as? String, "Bar")
    }

    private func valueExpectation(_ element: XCUIElement, equals value: Int) -> XCTNSPredicateExpectation {
        XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", NSNumber(value: value)),
            object: element
        )
    }
}

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

    func testSettingsOpensWithStableControlAccessibilityIdentifiers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture", "dashboard", "-uiTestSettingsSuite", "com.sanepeek.uitests.settings.\(UUID().uuidString)"]
        app.launch()

        app.descendants(matching: .any)["dashboard.settings"].click()

        let settingsRoot = app.descendants(matching: .any)["settings.root"]
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 5))

        for identifier in [
            "settings.appearance",
            "settings.refreshRate",
            "settings.byteUnitSystem",
            "settings.temperatureUnit",
            "settings.launchAtLogin"
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].exists,
                "Expected \(identifier) to exist in the Settings scene"
            )
        }
    }

    func testRefreshRateSettingPersistsAcrossRelaunch() throws {
        let suiteName = "com.sanepeek.uitests.settings.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture", "dashboard", "-uiTestSettingsSuite", suiteName]
        app.launch()

        app.descendants(matching: .any)["dashboard.settings"].click()
        let refreshRatePicker = app.descendants(matching: .any)["settings.refreshRate"]
        XCTAssertTrue(refreshRatePicker.waitForExistence(timeout: 5))

        refreshRatePicker.click()
        let fiveSecondsOption = app.descendants(matching: .any)["5 seconds"]
        XCTAssertTrue(fiveSecondsOption.waitForExistence(timeout: 5))
        fiveSecondsOption.click()

        app.terminate()
        app.launchArguments = ["-uiTestFixture", "dashboard", "-uiTestSettingsSuite", suiteName]
        app.launch()

        app.descendants(matching: .any)["dashboard.settings"].click()
        let reopenedPicker = app.descendants(matching: .any)["settings.refreshRate"]
        XCTAssertTrue(reopenedPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedPicker.value as? String, "5 seconds")
    }

    /// Exercises the real `SMAppService.mainApp` registration path (no fake
    /// service here, unlike `SettingsStoreTests`), because that's the one
    /// thing a unit test can't prove: that the live entitlements/signing on
    /// this build actually let registration succeed end to end. A teardown
    /// block guarantees the real login item is left disabled no matter how
    /// the test ends, since this toggle has a genuine, persistent system
    /// effect (visible in `sfltool dumpbtm`) beyond the app's own sandbox.
    func testLaunchAtLoginRegistersAndUnregistersWithTheRealSystemService() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture", "dashboard", "-uiTestSettingsSuite", "com.sanepeek.uitests.settings.\(UUID().uuidString)"]
        app.launch()

        app.descendants(matching: .any)["dashboard.settings"].click()
        let toggle = app.descendants(matching: .any)["settings.launchAtLogin"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        addTeardownBlock {
            guard toggle.exists, (toggle.value as? Int) == 1 else { return }
            toggle.click()
            self.waitForValue(1, of: toggle, toBecome: 0)
        }

        XCTAssertEqual(toggle.value as? Int, 0, "Expected Launch at Login to start disabled")

        toggle.click()
        waitForValue(0, of: toggle, toBecome: 1)
        XCTAssertEqual(toggle.value as? Int, 1, "Expected the toggle to reflect a successful registration")

        let statusMessage = app.descendants(matching: .any)["settings.launchAtLoginStatus"]
        XCTAssertFalse(statusMessage.exists, "A successful registration should not show a failure/approval message")

        toggle.click()
        waitForValue(1, of: toggle, toBecome: 0)
        XCTAssertEqual(toggle.value as? Int, 0, "Expected the toggle to reflect a successful unregistration")
    }

    private func waitForValue(_ from: Int, of element: XCUIElement, toBecome to: Int, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "value == %@", NSNumber(value: to))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter().wait(for: [expectation], timeout: timeout)
    }
}

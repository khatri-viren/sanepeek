//
//  SanePeekUITests.swift
//  SanePeekUITests
//

import AppKit
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

    /// The Settings picker only proves the model-level appearance mapping
    /// (already unit-tested in `SettingsStoreTests`); this test proves the
    /// setting actually reaches the rendered window via `.preferredColorScheme`
    /// in `SanePeekApp`, by sampling average screenshot brightness of the
    /// dashboard content rather than trusting the picker's own reported value.
    /// (The segmented control's own accessibility `value` isn't a string on
    /// macOS — reading it returns the AX subelement, not a display name —
    /// but each individual segment's `value` is a 0/1 checked indicator, so
    /// selection is read from the specific segment instead.)
    func testAppearanceSettingChangesRenderedInterfaceAndPersists() throws {
        let suiteName = "com.sanepeek.uitests.settings.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture", "dashboard", "-uiTestSettingsSuite", suiteName]
        app.launch()

        let dashboardRoot = app.descendants(matching: .any)["dashboard.root"]
        XCTAssertTrue(dashboardRoot.waitForExistence(timeout: 5))

        app.descendants(matching: .any)["dashboard.settings"].click()
        let appearancePicker = app.descendants(matching: .any)["settings.appearance"]
        XCTAssertTrue(appearancePicker.waitForExistence(timeout: 5))

        func selectAppearance(_ displayName: String) {
            let option = app.descendants(matching: .any)[displayName]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "Expected a \(displayName) appearance option")
            option.click()
        }

        selectAppearance("Light")
        let lightBrightness = Self.averageBrightness(of: dashboardRoot.screenshot().image)

        selectAppearance("Dark")
        let darkBrightness = Self.averageBrightness(of: dashboardRoot.screenshot().image)

        XCTAssertGreaterThan(
            lightBrightness - darkBrightness, 0.2,
            "Expected Light appearance to render a materially brighter dashboard than Dark"
        )

        selectAppearance("System")
        XCTAssertTrue(dashboardRoot.exists, "Expected the dashboard to keep rendering after switching to System appearance")

        selectAppearance("Dark")
        app.terminate()
        app.launchArguments = ["-uiTestFixture", "dashboard", "-uiTestSettingsSuite", suiteName]
        app.launch()

        app.descendants(matching: .any)["dashboard.settings"].click()
        let reopenedPicker = app.descendants(matching: .any)["settings.appearance"]
        XCTAssertTrue(reopenedPicker.waitForExistence(timeout: 5))
        let reopenedDarkOption = app.descendants(matching: .any)["Dark"]
        XCTAssertTrue(reopenedDarkOption.waitForExistence(timeout: 5))
        waitForValue(0, of: reopenedDarkOption, toBecome: 1)
        XCTAssertEqual(reopenedDarkOption.value as? Int, 1, "Expected Dark to remain selected after relaunch")
    }

    /// Smoke-tests two accessibility concerns that no other test covers:
    /// that VoiceOver has something meaningful to announce for a metric card,
    /// and that Settings can be reached and its controls read without ever
    /// touching the mouse. Doesn't test Tab/arrow-key control navigation:
    /// that only works when the user has "Full Keyboard Access" enabled in
    /// System Settings (`com.apple.universalaccess AppleKeyboardUIMode`,
    /// off by default — confirmed off in this environment) — the same
    /// system-wide precondition Apple's own System Settings app depends on.
    /// Depending on it here would mean either a flaky test or an automated
    /// test mutating the user's global accessibility preference as a side
    /// effect, neither of which is appropriate.
    func testKeyboardOpensSettingsWithoutTheMouseAndCardsExposeAccessibilityLabels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture", "dashboard", "-uiTestSettingsSuite", "com.sanepeek.uitests.settings.\(UUID().uuidString)"]
        app.launch()

        let cpuCard = app.descendants(matching: .any)["dashboard.card.cpu"]
        XCTAssertTrue(cpuCard.waitForExistence(timeout: 5))
        XCTAssertFalse(cpuCard.label.isEmpty, "Expected the CPU card to expose a non-empty accessibility label for VoiceOver")

        app.typeKey(",", modifierFlags: .command)
        let picker = app.descendants(matching: .any)["settings.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Expected Cmd+, to open Settings without using the mouse")
    }

    private func waitForValue(_ from: Int, of element: XCUIElement, toBecome to: Int, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "value == %@", NSNumber(value: to))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter().wait(for: [expectation], timeout: timeout)
    }

    /// Coarse grid-sampled average grayscale brightness (0 = black, 1 = white)
    /// of a screenshot, used only to detect a gross light-vs-dark difference —
    /// not a precise color assertion.
    private static func averageBrightness(of image: NSImage) -> Double {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return 0 }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return 0 }

        let strideX = max(width / 40, 1)
        let strideY = max(height / 40, 1)
        var total: Double = 0
        var count = 0

        for x in stride(from: 0, to: width, by: strideX) {
            for y in stride(from: 0, to: height, by: strideY) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += (Double(color.redComponent) + Double(color.greenComponent) + Double(color.blueComponent)) / 3
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }
}

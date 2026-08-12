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

    func testLaunchIsSilentWithoutFullWindow() throws {
        let harness = SanePeekUITestHarness()
        defer { harness.cleanup() }
        harness.launch()

        XCTAssertEqual(harness.app.windows.count, 0, "SanePeek should not create a full window at launch")
    }

    func testSettingsOpensFromTheStandardCommandAndUsesTheLargerPanel() throws {
        let harness = SanePeekUITestHarness()
        defer { harness.cleanup() }
        harness.launch()
        harness.openSettings()
        let app = harness.app

        let settingsRoot = app.descendants(matching: .any)["settings.root"]
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(settingsRoot.frame.width, 450, "Expected the Settings panel to use the wider default size")

        for identifier in [
            "settings.appearance",
            "settings.refreshRate",
            "settings.byteUnitSystem",
            "settings.temperatureUnit",
            "settings.launchAtLogin",
            "settings.version",
            "settings.checkForUpdates"
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].exists,
                "Expected (identifier) to exist in the Settings scene"
            )
        }
    }

    func testRefreshRateSettingPersistsAcrossRelaunch() throws {
        let harness = SanePeekUITestHarness()
        defer { harness.cleanup() }
        let app = harness.app

        harness.launch()
        harness.openSettings()
        let refreshRatePicker = app.descendants(matching: .any)["settings.refreshRate"]
        XCTAssertTrue(refreshRatePicker.waitForExistence(timeout: 5))

        refreshRatePicker.click()
        let fiveSecondsOption = app.descendants(matching: .any)["5 seconds"]
        XCTAssertTrue(fiveSecondsOption.waitForExistence(timeout: 5))
        fiveSecondsOption.click()

        harness.relaunch()
        harness.openSettings()

        let reopenedPicker = app.descendants(matching: .any)["settings.refreshRate"]
        XCTAssertTrue(reopenedPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedPicker.value as? String, "5 seconds")
    }

    func testAppearanceSettingChangesRenderedSettingsInterfaceAndPersists() throws {
        let harness = SanePeekUITestHarness()
        defer { harness.cleanup() }
        let app = harness.app

        harness.launch()
        harness.openSettings()
        let settingsRoot = app.descendants(matching: .any)["settings.root"]
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 5))
        let appearancePicker = app.descendants(matching: .any)["settings.appearance"]
        XCTAssertTrue(appearancePicker.waitForExistence(timeout: 5))

        func selectAppearance(_ displayName: String) {
            appearancePicker.click()
            let option = app.descendants(matching: .any)[displayName]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "Expected a (displayName) appearance option")
            option.click()
        }

        selectAppearance("Light")
        let lightBrightness = Self.averageBrightness(of: settingsRoot.screenshot().image)

        selectAppearance("Dark")
        let darkBrightness = Self.averageBrightness(of: settingsRoot.screenshot().image)

        XCTAssertGreaterThan(
            lightBrightness - darkBrightness,
            0.1,
            "Expected Light appearance to render a brighter Settings panel than Dark"
        )

        selectAppearance("System")
        XCTAssertTrue(settingsRoot.exists, "Expected Settings to keep rendering after switching to System appearance")

        selectAppearance("Dark")
        harness.relaunch()
        harness.openSettings()

        let reopenedAppearance = app.descendants(matching: .any)["settings.appearance"]
        XCTAssertTrue(reopenedAppearance.waitForExistence(timeout: 5))
        let reopenedDarkOption = app.descendants(matching: .any)["Dark"]
        XCTAssertTrue(reopenedDarkOption.waitForExistence(timeout: 5))
        waitForValue(0, of: reopenedDarkOption, toBecome: 1)
        XCTAssertEqual(reopenedDarkOption.value as? Int, 1, "Expected Dark to remain selected after relaunch")
    }

    /// The real registration path mutates persistent macOS state and is manual-only. Ordinary
    /// state coverage lives in the injected launch-at-login service tests.
    func testLaunchAtLoginRegistrationIsManualOnly() throws {
        throw XCTSkip("Manual-only: mutates the real macOS login-item registration")
    }

    func testCommandCommaOpensSettingsWithoutAHostWindow() throws {
        let harness = SanePeekUITestHarness()
        defer { harness.cleanup() }
        harness.launch()

        XCTAssertEqual(harness.app.windows.count, 0, "SanePeek should remain windowless until Settings is requested")
        harness.openSettings()

        XCTAssertTrue(harness.element("settings.appearance").waitForExistence(timeout: 5))
    }

    private func waitForValue(_ from: Int, of element: XCUIElement, toBecome to: Int, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "value == %@", NSNumber(value: to))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter().wait(for: [expectation], timeout: timeout)
    }

    /// Coarse grid-sampled average grayscale brightness (0 = black, 1 = white), used only to
    /// detect a gross light-vs-dark difference.
    private static func averageBrightness(of image: NSImage) -> Double {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return 0 }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return 0 }

        var total = 0.0
        var count = 0
        for y in stride(from: 0, to: height, by: max(1, height / 12)) {
            for x in stride(from: 0, to: width, by: max(1, width / 12)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }
}

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
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.windows.count, 0, "SanePeek should not create a full window at launch")
    }

    func testSettingsOpensFromTheStandardCommandAndUsesTheLargerPanel() throws {
        let app = launchSettings()

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
        let suiteName = "com.sanepeek.uitests.settings.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let app = launchSettings(suiteName: suiteName)
        let refreshRatePicker = app.descendants(matching: .any)["settings.refreshRate"]
        XCTAssertTrue(refreshRatePicker.waitForExistence(timeout: 5))

        refreshRatePicker.click()
        let fiveSecondsOption = app.descendants(matching: .any)["5 seconds"]
        XCTAssertTrue(fiveSecondsOption.waitForExistence(timeout: 5))
        fiveSecondsOption.click()

        app.terminate()
        app.launchArguments = ["-uiTestSettingsSuite", suiteName]
        app.launch()
        openSettings(in: app)

        let reopenedPicker = app.descendants(matching: .any)["settings.refreshRate"]
        XCTAssertTrue(reopenedPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedPicker.value as? String, "5 seconds")
    }

    func testAppearanceSettingChangesRenderedSettingsInterfaceAndPersists() throws {
        let suiteName = "com.sanepeek.uitests.settings.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let app = launchSettings(suiteName: suiteName)
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
        app.terminate()
        app.launchArguments = ["-uiTestSettingsSuite", suiteName]
        app.launch()
        openSettings(in: app)

        let reopenedAppearance = app.descendants(matching: .any)["settings.appearance"]
        XCTAssertTrue(reopenedAppearance.waitForExistence(timeout: 5))
        let reopenedDarkOption = app.descendants(matching: .any)["Dark"]
        XCTAssertTrue(reopenedDarkOption.waitForExistence(timeout: 5))
        waitForValue(0, of: reopenedDarkOption, toBecome: 1)
        XCTAssertEqual(reopenedDarkOption.value as? Int, 1, "Expected Dark to remain selected after relaunch")
    }

    /// Exercises the real `SMAppService.mainApp` registration path and leaves the system login
    /// item disabled after the test, since this toggle has a genuine persistent system effect.
    func testLaunchAtLoginRegistersAndUnregistersWithTheRealSystemService() throws {
        let app = launchSettings()
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
        XCTAssertFalse(app.descendants(matching: .any)["settings.launchAtLoginStatus"].exists)

        toggle.click()
        waitForValue(1, of: toggle, toBecome: 0)
        XCTAssertEqual(toggle.value as? Int, 0, "Expected the toggle to reflect a successful unregistration")
    }

    func testCommandCommaOpensSettingsWithoutAHostWindow() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.windows.count, 0, "SanePeek should remain windowless until Settings is requested")
        openSettings(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance"].waitForExistence(timeout: 5))
    }

    private func launchSettings(suiteName: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let suiteName {
            app.launchArguments = ["-uiTestSettingsSuite", suiteName]
        }
        app.launch()
        openSettings(in: app)
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)
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

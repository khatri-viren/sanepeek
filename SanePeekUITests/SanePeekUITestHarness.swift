//
//  SanePeekUITestHarness.swift
//  SanePeekUITests
//

import XCTest

@MainActor
final class SanePeekUITestHarness {
    let app: XCUIApplication
    let suiteName: String

    init(
        fixture: String? = nil,
        menuBarSeed: String? = nil,
        suiteName: String = "com.sanepeek.uitests.\(UUID().uuidString)"
    ) {
        self.app = XCUIApplication()
        self.suiteName = suiteName
        configureLaunch(fixture: fixture, menuBarSeed: menuBarSeed)
    }

    func launch() {
        app.launch()
    }

    func relaunch(fixture: String? = nil, menuBarSeed: String? = nil) {
        app.terminate()
        configureLaunch(fixture: fixture, menuBarSeed: menuBarSeed)
        app.launch()
    }

    func openSettings() {
        app.typeKey(",", modifierFlags: .command)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    func metricRow(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
    }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) {
        app.terminate()
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 5),
            "UI test app should terminate during harness cleanup",
            file: file,
            line: line
        )

        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("UI test suite defaults should be available during cleanup", file: file, line: line)
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName),
            "UI test suite defaults should be removed during cleanup",
            file: file,
            line: line
        )
    }

    private func configureLaunch(fixture: String?, menuBarSeed: String?) {
        var arguments = ["-uiTestSettingsSuite", suiteName]
        if let fixture {
            arguments += ["-uiTestFixture", fixture]
        }
        if let menuBarSeed {
            arguments += ["-uiTestMenuBar", menuBarSeed]
        }
        app.launchArguments = arguments
    }
}

//
//  MonitorWindowUITests.swift
//  SanePeekUITests
//

import XCTest

@MainActor
final class MonitorWindowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStatusItemOpensSemanticMonitorAndHandsOffBetweenMetrics() throws {
        let harness = SanePeekUITestHarness(
            fixture: "baseline",
            menuBarSeed: "cpu:number,memory:bar"
        )
        defer { harness.cleanup() }
        harness.launch()

        let cpuStatusItem = harness.element("menuBar.metric.cpu")
        XCTAssertTrue(cpuStatusItem.waitForExistence(timeout: 10))
        cpuStatusItem.click()

        let monitor = harness.element("monitor.window")
        XCTAssertTrue(monitor.waitForExistence(timeout: 10))
        let memoryRow = harness.metricRow("Memory")
        XCTAssertTrue(memoryRow.waitForExistence(timeout: 5))

        memoryRow.click()
        XCTAssertTrue(monitor.exists)
        XCTAssertTrue(memoryRow.exists)

        cpuStatusItem.click()
        XCTAssertTrue(monitor.waitForExistence(timeout: 5))
        XCTAssertTrue(harness.metricRow("CPU").waitForExistence(timeout: 5))

        cpuStatusItem.click()
        XCTAssertTrue(monitor.waitForNonExistence(timeout: 5))
    }

    func testUnavailableFixtureKeepsTheMonitorSemanticAndExplainsTheDegradation() throws {
        let harness = SanePeekUITestHarness(
            fixture: "unavailable",
            menuBarSeed: "cpu:number"
        )
        defer { harness.cleanup() }
        harness.launch()

        let cpuStatusItem = harness.element("menuBar.metric.cpu")
        XCTAssertTrue(cpuStatusItem.waitForExistence(timeout: 10))
        cpuStatusItem.click()

        let monitor = harness.element("monitor.window")
        if !monitor.waitForExistence(timeout: 10) {
            cpuStatusItem.click()
        }
        XCTAssertTrue(monitor.waitForExistence(timeout: 5))
        XCTAssertTrue(
            harness.app.staticTexts["This metric is temporarily unavailable."].waitForExistence(timeout: 5)
        )
    }

    func testMonitorSettingsEscapeAndQuitActionsFollowTheWindowLifecycle() throws {
        let harness = SanePeekUITestHarness(
            fixture: "baseline",
            menuBarSeed: "cpu:number"
        )
        defer { harness.cleanup() }

        harness.launch()
        let cpuStatusItem = harness.element("menuBar.metric.cpu")
        XCTAssertTrue(cpuStatusItem.waitForExistence(timeout: 10))
        cpuStatusItem.click()
        XCTAssertTrue(harness.element("monitor.window").waitForExistence(timeout: 10))

        harness.app.buttons["Settings"].click()
        XCTAssertTrue(harness.element("settings.root").waitForExistence(timeout: 5))

        harness.relaunch(fixture: "baseline", menuBarSeed: "cpu:number")
        let reopenedCPUStatusItem = harness.element("menuBar.metric.cpu")
        XCTAssertTrue(reopenedCPUStatusItem.waitForExistence(timeout: 10))
        reopenedCPUStatusItem.click()
        let monitor = harness.element("monitor.window")
        XCTAssertTrue(monitor.waitForExistence(timeout: 10))

        harness.app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(monitor.waitForNonExistence(timeout: 5))

        reopenedCPUStatusItem.click()
        XCTAssertTrue(monitor.waitForExistence(timeout: 5))
        harness.app.buttons["Quit SanePeek"].click()
        XCTAssertTrue(harness.app.wait(for: .notRunning, timeout: 5))
    }

    func testMixedFailureFixtureStillRendersEveryMetricRow() throws {
        let harness = SanePeekUITestHarness(
            fixture: "mixedFailure",
            menuBarSeed: "cpu:number"
        )
        defer { harness.cleanup() }
        harness.launch()

        let cpuStatusItem = harness.element("menuBar.metric.cpu")
        XCTAssertTrue(cpuStatusItem.waitForExistence(timeout: 10))
        cpuStatusItem.click()

        XCTAssertTrue(harness.element("monitor.window").waitForExistence(timeout: 10))
        for kind in ["cpu", "memory", "storage", "network", "battery", "gpu", "temperature"] {
            let title: String = switch kind {
            case "cpu": "CPU"
            case "gpu": "GPU"
            default: kind.capitalized
            }
            XCTAssertTrue(
                harness.metricRow(title).waitForExistence(timeout: 5),
                "Expected the mixed-failure fixture to keep the \(kind) row visible"
            )
        }
    }

    func testEveryFixtureProducesADeterministicMonitorJourney() throws {
        let harness = SanePeekUITestHarness(menuBarSeed: "cpu:number")
        defer { harness.cleanup() }

        let fixtures = [
            "baseline",
            "warning",
            "critical",
            "unavailable",
            "gpuUnsupported",
            "mixedFailure",
            "temperatureUnsupported"
        ]

        for fixture in fixtures {
            harness.relaunch(fixture: fixture, menuBarSeed: "cpu:number")

            let cpuStatusItem = harness.element("menuBar.metric.cpu")
            XCTAssertTrue(cpuStatusItem.waitForExistence(timeout: 10), "Expected CPU status item for (fixture)")
            cpuStatusItem.click()

            let monitor = harness.element("monitor.window")
            XCTAssertTrue(monitor.waitForExistence(timeout: 10), "Expected monitor window for (fixture)")
            XCTAssertTrue(harness.metricRow("CPU").waitForExistence(timeout: 5), "Expected CPU row for (fixture)")

            switch fixture {
            case "unavailable":
                XCTAssertTrue(
                    harness.app.staticTexts["This metric is temporarily unavailable."].waitForExistence(timeout: 5),
                    "Expected unavailable copy for (fixture)"
                )
            case "gpuUnsupported":
                XCTAssertTrue(
                    harness.metricRow("GPU").waitForNonExistence(timeout: 5),
                    "Expected unsupported GPU card to be hidden"
                )
            case "mixedFailure":
                let storageRow = harness.metricRow("Storage")
                XCTAssertTrue(storageRow.waitForExistence(timeout: 5))
                storageRow.click()
                XCTAssertTrue(
                    harness.app.staticTexts["No data is available yet."].waitForExistence(timeout: 5),
                    "Expected Storage degradation copy for (fixture)"
                )
            case "temperatureUnsupported":
                let temperatureRow = harness.metricRow("Temperature")
                XCTAssertTrue(temperatureRow.waitForExistence(timeout: 5))
                temperatureRow.click()
                XCTAssertTrue(
                    harness.app.staticTexts["This metric is not supported on this Mac."].waitForExistence(timeout: 5),
                    "Expected Temperature degradation copy for (fixture)"
                )
            default:
                break
            }
        }
    }
}

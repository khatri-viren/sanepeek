//
//  SanePeekPerformanceTests.swift
//  SanePeekPerformanceTests
//

import AppKit
import XCTest

@testable import SanePeek

/// Deterministic performance budgets for the parts of the app that run continuously or sit on
/// the menu-bar interaction path. These are intentionally separate from correctness tests:
/// XCTest records the measurements, while the baseline artifact and release checklist decide
/// whether a change is acceptable on a given machine.
@MainActor
final class SanePeekPerformanceTests: XCTestCase {
    private static let baseline = MetricFixtures.baseline()

    override func tearDown() {
        MenuBarLabelImage.resetRenderCacheForTesting()
        super.tearDown()
    }

    func testMetricsEngineFastAndSlowSamplingAndMergeCost() {
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let completed = expectation(description: "first deterministic observation")
            let engine = Self.makeEngine()

            Task {
                let stream = await engine.observations()
                await engine.start()
                for await _ in stream {
                    await engine.stop()
                    completed.fulfill()
                    return
                }
            }

            wait(for: [completed], timeout: 5)
        }
    }

    func testMetricsEngineActiveMetricFilteringCost() {
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            let completed = expectation(description: "active metric updates")
            let engine = Self.makeEngine()
            let activeSets: [Set<MetricKind>] = [
                [.cpu],
                [.cpu, .memory, .network],
                Set(MetricKind.allCases)
            ]

            Task {
                for _ in 0..<200 {
                    for activeSet in activeSets {
                        await engine.setActiveMetrics(activeSet)
                    }
                }
                await engine.stop()
                completed.fulfill()
            }

            wait(for: [completed], timeout: 5)
        }
    }

    func testMetricsViewModelAppliesACompleteBoundedTick() {
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let feed = PerformanceTickFeed()
            let viewModel = MetricsViewModel(feed: feed)
            feed.send(Self.tick)

            let deadline = Date().addingTimeInterval(2)
            while !viewModel.hasReceivedData && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            }

            XCTAssertTrue(viewModel.hasReceivedData)
            XCTAssertEqual(viewModel.cards.count, 3)
        }
    }

    func testMenuBarLabelImageGenerationForNumberAndBarModes() {
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for iteration in 0..<50 {
                for kind in MetricKind.allCases {
                    _ = MenuBarLabelImage.renderedImage(
                        kind: kind,
                        displayMode: .number,
                        value: "(iteration)%",
                        fraction: Double(iteration % 100) / 100,
                        tint: nil
                    )
                    _ = MenuBarLabelImage.renderedImage(
                        kind: kind,
                        displayMode: .bar,
                        value: "(iteration)%",
                        fraction: Double(iteration % 100) / 100,
                        tint: nil
                    )
                }
            }
        }
    }

    func testMonitorWindowContentUpdateAndMetricHandoffCost() {
        let suiteName = "com.sanepeek.performance.(UUID().uuidString)"
        let appState = AppState(
            dependencies: AppDependencies(
                runtime: .preview,
                fixtureSnapshot: Self.baseline,
                settingsDefaultsSuiteName: suiteName,
                menuBarSeed: Dictionary(uniqueKeysWithValues: MetricKind.allCases.map {
                    ($0, MenuBarMetricConfig(isEnabled: true, displayMode: .number))
                })
            )
        )
        let controller = MenuBarPopoverController()
        controller.configure(appState: appState)

        defer {
            controller.tearDown()
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            XCTAssertTrue(controller.selectStatusItem(.cpu))
            XCTAssertTrue(controller.selectStatusItem(.memory))
            XCTAssertTrue(controller.selectStatusItem(.network))
            XCTAssertTrue(controller.selectStatusItem(.temperature))
            XCTAssertTrue(controller.selectStatusItem(.temperature))
        }
    }

    private static let tick: MetricsTick = {
        let snapshot = baseline
        let history = Array(repeating: 0.5, count: 128)
        return MetricsTick(
            snapshot: snapshot,
            cpuHistory: history,
            cpuUserHistory: history,
            cpuSystemHistory: history,
            memoryHistory: history,
            memoryAppHistory: history,
            memoryWiredHistory: history,
            memoryCompressedHistory: history,
            networkDownloadHistory: history,
            networkUploadHistory: history,
            gpuHistory: history,
            temperatureHistory: history
        )
    }()

    private static func makeEngine() -> MetricsEngine {
        MetricsEngine(
            cpuReader: PerformanceMetricReader(snapshot: baseline.cpu!),
            memoryReader: PerformanceMetricReader(snapshot: baseline.memory!),
            storageReader: PerformanceMetricReader(snapshot: baseline.storage!),
            networkReader: PerformanceMetricReader(snapshot: baseline.network!),
            batteryReader: PerformanceMetricReader(snapshot: baseline.battery!),
            gpuReader: PerformanceMetricReader(snapshot: baseline.gpu!),
            temperatureReader: PerformanceMetricReader(snapshot: baseline.temperature!),
            fastScheduler: ImmediateMetricScheduler(),
            slowScheduler: ImmediateMetricScheduler()
        )
    }
}

@MainActor
private final class PerformanceTickFeed: MetricsTickFeed {
    private let stream: AsyncStream<MetricsTick>
    private let continuation: AsyncStream<MetricsTick>.Continuation

    init() {
        var continuation: AsyncStream<MetricsTick>.Continuation?
        stream = AsyncStream { continuation = $0 }
        guard let continuation else {
            preconditionFailure("Unable to create performance tick stream")
        }
        self.continuation = continuation
    }

    func ticks() -> AsyncStream<MetricsTick> { stream }

    func send(_ tick: MetricsTick) {
        continuation.yield(tick)
    }
}

private struct ImmediateMetricScheduler: MetricScheduler {
    func wait(for interval: TimeInterval) async throws {}
}

private actor PerformanceMetricReader<Snapshot: MetricSnapshot>: MetricReader {
    let snapshot: Snapshot

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<Snapshot> {
        .available(snapshot)
    }
}

extension PerformanceMetricReader: CPUReader where Snapshot == CPUSnapshot {}
extension PerformanceMetricReader: MemoryReader where Snapshot == MemorySnapshot {}
extension PerformanceMetricReader: StorageReader where Snapshot == StorageSnapshot {}
extension PerformanceMetricReader: NetworkReader where Snapshot == NetworkSnapshot {}
extension PerformanceMetricReader: BatteryReader where Snapshot == BatterySnapshot {}
extension PerformanceMetricReader: GPUReader where Snapshot == GPUSnapshot {}
extension PerformanceMetricReader: TemperatureReader where Snapshot == TemperatureSnapshot {}

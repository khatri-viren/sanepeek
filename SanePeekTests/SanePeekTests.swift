//
//  SanePeekTests.swift
//  SanePeekTests
//

import Foundation
import Testing
@testable import SanePeek

struct SanePeekTests {

    @Test("Metric readers return typed snapshots without OS coupling")
    func metricReadersReturnTypedSnapshots() async {
        let timestamp = MetricTimestamp.zero
        let cpu = CPUSnapshot(timestamp: timestamp, utilization: 0.25)
        let reader = FixtureCPUReader(result: .available(cpu))

        let result = await reader.read(at: timestamp)

        #expect(result.value == cpu)
        #expect(result.availability == .available)

        let failure = MetricFailure(kind: .permissionDenied)
        let failedReader = FixtureCPUReader(result: .failed(failure))
        let failedResult = await failedReader.read(at: timestamp)

        #expect(failedResult.value == nil)
        #expect(failedResult.availability == .failed(failure))
    }

    @Test("Refresh cadence and clocks are injectable and deterministic")
    func refreshCadenceAndClocksAreDeterministic() async throws {
        let clock = TestMetricClock(startingAt: .zero).advanced(by: 2.5)

        #expect(clock.now().monotonicSeconds == 2.5)
        #expect(clock.now().date == Date(timeIntervalSince1970: 2.5))

        let oneSecond = CadencePolicy(refreshRate: .oneSecond)
        let twoSeconds = CadencePolicy(refreshRate: .twoSeconds)
        let fiveSeconds = CadencePolicy(refreshRate: .fiveSeconds)

        #expect(oneSecond.interval(for: .cpu) == 1)
        #expect(twoSeconds.interval(for: .memory) == 2)
        #expect(fiveSeconds.interval(for: .network) == 5)
        #expect(oneSecond.interval(for: .gpu) == 1)
        #expect(twoSeconds.interval(for: .storage) == 30)
        #expect(fiveSeconds.interval(for: .battery) == 30)

        let scheduler: any MetricScheduler = ImmediateMetricScheduler()
        try await scheduler.wait(for: 0)
    }

    @Test("Metric fixtures provide a complete OS-independent snapshot")
    func metricFixturesProvideCompleteSnapshot() {
        let snapshot = MetricFixtures.dashboard(at: .zero)

        #expect(snapshot.timestamp == .zero)
        #expect(snapshot.cpu?.availability == .available)
        #expect(snapshot.memory?.availability == .available)
        #expect(snapshot.storage?.availability == .available)
        #expect(snapshot.network?.availability == .available)
        #expect(snapshot.battery?.availability == .available)
        #expect(snapshot.gpu?.availability == .available)
        #expect(snapshot.containsAvailableMetric)
    }

    @Test("Metric results preserve available, unavailable, and failed states")
    func metricResultsPreserveSafeStates() {
        let available: MetricResult<Int> = .available(42)
        #expect(available.value == 42)
        #expect(available.isAvailable)
        #expect(available.availability == .available)

        let unavailable: MetricResult<Int> = .unavailable(.unsupported)
        #expect(unavailable.value == nil)
        #expect(!unavailable.isAvailable)
        #expect(unavailable.availability == .unavailable(.unsupported))

        let failure = MetricFailure(kind: .systemUnavailable)
        let failed: MetricResult<Int> = .failed(failure)
        #expect(failed.value == nil)
        #expect(failed.availability == .failed(failure))
        #expect(failed.userMessage == "This metric is temporarily unavailable.")
    }

    @Test("Metric snapshots preserve values and explicit unavailable paths")
    func metricSnapshotsPreserveValuesAndUnavailablePaths() {
        let timestamp = MetricTimestamp.zero
        let cpu = CPUSnapshot(
            timestamp: timestamp,
            utilization: 0.42,
            logicalCoreCount: 10,
            performanceCoreCount: 6,
            efficiencyCoreCount: 4
        )

        #expect(cpu.availability == .available)
        #expect(cpu.utilization == 0.42)
        #expect(cpu.logicalCoreCount == 10)
        #expect(cpu.performanceCoreCount == 6)
        #expect(cpu.efficiencyCoreCount == 4)

        let memory = MemorySnapshot(
            timestamp: timestamp,
            usedBytes: 8_000,
            availableBytes: 2_000,
            pressure: .normal
        )
        let bundle = MetricsSnapshot(timestamp: timestamp, cpu: cpu, memory: memory)

        #expect(bundle.cpu == cpu)
        #expect(bundle.memory == memory)
        #expect(bundle.storage == nil)

        let unavailableCPU = CPUSnapshot.unavailable(at: timestamp, reason: .unsupported)
        let unavailableMemory = MemorySnapshot.unavailable(at: timestamp, reason: .noData)
        let unavailableStorage = StorageSnapshot.unavailable(at: timestamp, reason: .temporarilyUnavailable)
        let unavailableNetwork = NetworkSnapshot.unavailable(at: timestamp, reason: .unsupported)
        let unavailableBattery = BatterySnapshot.unavailable(at: timestamp, reason: .notPresent)
        let unavailableGPU = GPUSnapshot.unavailable(at: timestamp, reason: .unsupported)

        #expect(unavailableCPU.utilization == nil)
        #expect(unavailableMemory.usedBytes == nil)
        #expect(unavailableStorage.totalBytes == nil)
        #expect(unavailableNetwork.downloadBytesPerSecond == nil)
        #expect(unavailableBattery.percentage == nil)
        #expect(unavailableGPU.utilization == nil)
        #expect(!unavailableCPU.availability.isAvailable)
        #expect(!unavailableMemory.availability.isAvailable)
        #expect(!unavailableStorage.availability.isAvailable)
        #expect(!unavailableNetwork.availability.isAvailable)
        #expect(!unavailableBattery.availability.isAvailable)
        #expect(!unavailableGPU.availability.isAvailable)
    }

    @Test("App state defaults to live dependencies")
    @MainActor
    func appStateUsesLiveDependenciesByDefault() {
        let appState = AppState()

        #expect(appState.dependencies.runtime == .live)
    }

    @Test("App state accepts preview dependencies")
    @MainActor
    func appStateAcceptsPreviewDependencies() {
        let appState = AppState(dependencies: .preview)

        #expect(appState.dependencies.runtime == .preview)
    }

    @Test("Preview dependencies provide fixture metric snapshots")
    @MainActor
    func previewDependenciesProvideFixtureSnapshots() {
        #expect(AppDependencies.live.fixtureSnapshot == nil)
        #expect(AppDependencies.preview.fixtureSnapshot?.containsAvailableMetric == true)
    }
}

private struct FixtureCPUReader: CPUReader {
    let result: MetricResult<CPUSnapshot>

    func read(at timestamp: MetricTimestamp) async -> MetricResult<CPUSnapshot> {
        result
    }
}

private struct ImmediateMetricScheduler: MetricScheduler {
    func wait(for interval: TimeInterval) async throws {}
}

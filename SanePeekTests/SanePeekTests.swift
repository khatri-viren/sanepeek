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

    @Test("Metric history retains recent samples and rejects late samples")
    func metricHistoryRetainsRecentSamplesAndRejectsLateSamples() {
        var history = MetricRingBuffer<Double>(retention: 60, capacity: 2)
        let start = MetricTimestamp.zero

        let acceptedFirst = history.append(MetricSample(timestamp: start, value: 1))
        let acceptedSecond = history.append(MetricSample(timestamp: start.advanced(by: 30), value: 2))
        let acceptedThird = history.append(MetricSample(timestamp: start.advanced(by: 60), value: 3))

        #expect(acceptedFirst)
        #expect(acceptedSecond)
        #expect(acceptedThird)

        #expect(history.samples.map(\.value) == [2, 3])
        #expect(history.samples.first?.timestamp == start.advanced(by: 30))
        #expect(history.samples.last?.timestamp == start.advanced(by: 60))

        let rejectedLateSample = history.append(MetricSample(timestamp: start.advanced(by: 45), value: 99))

        #expect(!rejectedLateSample)
        #expect(history.samples.map(\.value) == [2, 3])
    }

    @Test("Metric history expires samples outside its retention window")
    func metricHistoryExpiresSamplesOutsideRetentionWindow() {
        var history = MetricRingBuffer<Double>(retention: 60, capacity: 10)
        let start = MetricTimestamp.zero

        _ = history.append(MetricSample(timestamp: start, value: 1))
        _ = history.append(MetricSample(timestamp: start.advanced(by: 60), value: 2))
        _ = history.append(MetricSample(timestamp: start.advanced(by: 61), value: 3))

        #expect(history.samples.map(\.value) == [2, 3])
        #expect(history.oldest?.timestamp == start.advanced(by: 60))
    }

    @Test("CPU utilization uses monotonic counter deltas")
    func cpuUtilizationUsesMonotonicCounterDeltas() {
        let previous = CPUCounterSample(
            timestamp: .zero,
            userTicks: 10,
            systemTicks: 10,
            idleTicks: 80
        )
        let current = CPUCounterSample(
            timestamp: .zero.advanced(by: 2),
            userTicks: 20,
            systemTicks: 20,
            idleTicks: 160
        )

        let result = CPUUtilizationCalculator.calculate(from: previous, to: current)

        #expect(result.isAvailable)
        #expect(abs((result.value ?? -1) - 0.2) < 0.0001)
    }

    @Test("CPU counter resets and zero-duration samples are unavailable")
    func cpuCounterResetsAndZeroDurationSamplesAreUnavailable() {
        let previous = CPUCounterSample(
            timestamp: .zero,
            userTicks: 10,
            systemTicks: 10,
            idleTicks: 80
        )
        let reset = CPUCounterSample(
            timestamp: .zero.advanced(by: 1),
            userTicks: 1,
            systemTicks: 1,
            idleTicks: 1
        )
        let sameTimestamp = CPUCounterSample(
            timestamp: .zero,
            userTicks: 11,
            systemTicks: 11,
            idleTicks: 81
        )

        let resetResult = CPUUtilizationCalculator.calculate(from: previous, to: reset)
        let zeroDurationResult = CPUUtilizationCalculator.calculate(from: previous, to: sameTimestamp)

        #expect(resetResult.availability == .unavailable(.noData))
        #expect(zeroDurationResult.availability == .unavailable(.noData))
    }

    @Test("CPU counter rollover uses an explicit counter maximum")
    func cpuCounterRolloverUsesExplicitCounterMaximum() {
        let previous = CPUCounterSample(
            timestamp: .zero,
            userTicks: 98,
            systemTicks: 0,
            idleTicks: 0
        )
        let current = CPUCounterSample(
            timestamp: .zero.advanced(by: 1),
            userTicks: 2,
            systemTicks: 0,
            idleTicks: 0
        )

        let result = CPUUtilizationCalculator.calculate(
            from: previous,
            to: current,
            counterMaximum: 100
        )

        #expect(result.value == 1)
    }

    @Test("Network throughput excludes loopback and invalid interfaces")
    func networkThroughputExcludesLoopbackAndInvalidInterfaces() {
        let previous = NetworkCounterSample(
            timestamp: .zero,
            interfaces: [
                NetworkInterfaceCounter(name: "en0", downloadBytes: 100, uploadBytes: 50),
                NetworkInterfaceCounter(
                    name: "lo0",
                    downloadBytes: 10_000,
                    uploadBytes: 10_000,
                    isLoopback: true
                ),
                NetworkInterfaceCounter(
                    name: "invalid0",
                    downloadBytes: 20_000,
                    uploadBytes: 20_000,
                    isValid: false
                )
            ]
        )
        let current = NetworkCounterSample(
            timestamp: .zero.advanced(by: 2),
            interfaces: [
                NetworkInterfaceCounter(name: "en0", downloadBytes: 300, uploadBytes: 90),
                NetworkInterfaceCounter(
                    name: "lo0",
                    downloadBytes: 110_000,
                    uploadBytes: 110_000,
                    isLoopback: true
                ),
                NetworkInterfaceCounter(
                    name: "invalid0",
                    downloadBytes: 220_000,
                    uploadBytes: 220_000,
                    isValid: false
                )
            ]
        )

        let result = NetworkThroughputCalculator.calculate(from: previous, to: current)

        #expect(result.value?.downloadBytesPerSecond == 100)
        #expect(result.value?.uploadBytesPerSecond == 20)
    }

    @Test("Network counters handle reset and rollover")
    func networkCountersHandleResetAndRollover() {
        let previous = NetworkCounterSample(
            timestamp: .zero,
            interfaces: [
                NetworkInterfaceCounter(name: "en0", downloadBytes: 98, uploadBytes: 90)
            ]
        )
        let reset = NetworkCounterSample(
            timestamp: .zero.advanced(by: 1),
            interfaces: [
                NetworkInterfaceCounter(name: "en0", downloadBytes: 2, uploadBytes: 1)
            ]
        )

        let resetResult = NetworkThroughputCalculator.calculate(from: previous, to: reset)
        #expect(resetResult.availability == .unavailable(.noData))

        let rolloverResult = NetworkThroughputCalculator.calculate(
            from: previous,
            to: reset,
            counterMaximum: 100
        )

        #expect(rolloverResult.value?.downloadBytesPerSecond == 5)
        #expect(rolloverResult.value?.uploadBytesPerSecond == 12)
    }

    @Test("Memory page conversion produces byte-based snapshots")
    func memoryPageConversionProducesByteBasedSnapshots() {
        let pages = MemoryPageCounts(usedPages: 3, availablePages: 2)

        let result = MemoryByteConverter.snapshot(
            from: pages,
            pageSize: 4_096,
            timestamp: .zero,
            pressure: .warning
        )

        #expect(result.value?.usedBytes == 12_288)
        #expect(result.value?.availableBytes == 8_192)
        #expect(result.value?.pressure == .warning)
    }

    @Test("Metric formatter supports decimal and binary byte units")
    func metricFormatterSupportsDecimalAndBinaryByteUnits() {
        let decimal = MetricFormatter(byteUnitSystem: .decimal)
        let binary = MetricFormatter(byteUnitSystem: .binary)

        #expect(decimal.bytes(1_500) == "1.5 kB")
        #expect(binary.bytes(1_048_576) == "1 MiB")
    }

    @Test("Metric formatter clamps percentages and preserves unavailable messages")
    func metricFormatterClampsPercentagesAndPreservesUnavailableMessages() {
        let formatter = MetricFormatter()
        let unavailable: MetricResult<Double> = .unavailable(.noData)
        let failed: MetricResult<Double> = .failed(MetricFailure(kind: .permissionDenied))

        #expect(formatter.percentage(-0.25) == "0%")
        #expect(formatter.percentage(1.25) == "100%")
        #expect(formatter.percentage(0.425, fractionDigits: 1) == "42.5%")
        #expect(formatter.percentage(unavailable) == "No data is available yet.")
        #expect(formatter.percentage(failed) == "This metric is unavailable due to system permissions.")
    }

    @Test("Metric formatter handles duration and temperature units")
    func metricFormatterHandlesDurationAndTemperatureUnits() {
        let celsius = MetricFormatter(temperatureUnit: .celsius)
        let fahrenheit = MetricFormatter(temperatureUnit: .fahrenheit)

        #expect(celsius.duration(59) == "59s")
        #expect(celsius.duration(3_661) == "1h 1m")
        #expect(celsius.temperature(21.5) == "21.5 °C")
        #expect(fahrenheit.temperature(0) == "32 °F")
    }

    @Test("Metric formatter renders unavailable and failed values safely")
    func metricFormatterRendersUnavailableAndFailedValuesSafely() {
        let formatter = MetricFormatter()
        let noData: MetricResult<UInt64> = .unavailable(.noData)
        let invalid: MetricResult<Double> = .failed(MetricFailure(kind: .invalidData))

        #expect(formatter.bytes(noData) == "No data is available yet.")
        #expect(formatter.temperature(invalid) == "The metric data is unavailable.")
        #expect(formatter.duration(.nan) == "Unavailable")
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

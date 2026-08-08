//
//  MetricsEngineTests.swift
//  SanePeekTests
//

import Foundation
import Testing
@testable import SanePeek

struct MetricsEngineTests {

    @Test("Fast and slow loops request cadence-specific intervals")
    func loopsRequestCadenceSpecificIntervals() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let engine = MetricsEngine(
            cpuReader: QueueingReader(results: [.available(CPUSnapshot(timestamp: .zero, utilization: 0.5))]),
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 100))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler,
            cadencePolicy: CadencePolicy(refreshRate: .twoSeconds)
        )

        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        await slowScheduler.waitUntilIntervalsCount(1)

        #expect(await fastScheduler.requestedIntervals == [2])
        #expect(await slowScheduler.requestedIntervals == [30])

        await engine.stop()
    }

    @Test("Start, pause, and resume control whether polling reads occur")
    func lifecycleControlsPolling() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let cpuReader = QueueingReader<CPUSnapshot>(
            results: Array(repeating: .available(CPUSnapshot(timestamp: .zero, utilization: 0.4)), count: 10)
        )
        let engine = MetricsEngine(
            cpuReader: cpuReader,
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        await engine.start()
        await engine.start() // idempotent: must not spawn a second loop
        await fastScheduler.waitUntilIntervalsCount(1)
        #expect(await cpuReader.callCount == 1)

        await engine.pause()
        await engine.pause() // idempotent
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(await cpuReader.callCount == 1)

        await engine.resume()
        await fastScheduler.waitUntilIntervalsCount(2)
        #expect(await cpuReader.callCount == 2)

        await engine.stop()
        await engine.stop() // idempotent
    }

    @Test("stop() cancels polling and finishes the snapshot stream")
    func stopFinishesStream() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let engine = MetricsEngine(
            cpuReader: QueueingReader(results: [.available(CPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        let stream = await engine.snapshots()
        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        await slowScheduler.waitUntilIntervalsCount(1)

        await engine.stop()

        var received: [MetricsSnapshot] = []
        for await snapshot in stream {
            received.append(snapshot)
        }

        // The for-await-in loop above only exits once stop() finishes the continuation.
        #expect(!received.isEmpty)
    }

    @Test("Refresh rate changes restart only the fast loop without duplicating samples")
    func refreshRateChangeDoesNotDuplicateSamples() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let cpuReader = QueueingReader<CPUSnapshot>(
            results: Array(repeating: .available(CPUSnapshot(timestamp: .zero, utilization: 0.3)), count: 10)
        )
        let engine = MetricsEngine(
            cpuReader: cpuReader,
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler,
            cadencePolicy: CadencePolicy(refreshRate: .oneSecond)
        )

        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        #expect(await fastScheduler.requestedIntervals == [1])
        #expect(await cpuReader.callCount == 1)

        await engine.updateCadence(CadencePolicy(refreshRate: .fiveSeconds))
        await fastScheduler.waitUntilIntervalsCount(2)

        // Exactly one more read must have happened for the restarted loop, not two.
        #expect(await cpuReader.callCount == 2)
        #expect(await fastScheduler.requestedIntervals == [1, 5])

        await engine.stop()
    }

    @Test("Pausing prevents new reads until resumed")
    func pausingPreventsNewReads() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let cpuReader = QueueingReader<CPUSnapshot>(
            results: Array(repeating: .available(CPUSnapshot(timestamp: .zero, utilization: 0.2)), count: 10)
        )
        let engine = MetricsEngine(
            cpuReader: cpuReader,
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        #expect(await cpuReader.callCount == 1)

        await engine.pause()
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(await cpuReader.callCount == 1)

        await engine.stop()
    }

    @Test("A failed reader does not block other metrics from publishing")
    func failedReaderDoesNotBlockOthers() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let failure = MetricFailure(kind: .systemUnavailable)
        let engine = MetricsEngine(
            cpuReader: QueueingReader<CPUSnapshot>(results: [.failed(failure)]),
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 42))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)

        let snapshot = await engine.currentSnapshot()
        #expect(snapshot.cpu?.availability == .failed(failure))
        #expect(snapshot.memory?.availability == .available)
        #expect(snapshot.memory?.usedBytes == 42)

        await engine.stop()
    }

    @Test("A read failure preserves the last known good value while marking unavailability")
    func lastKnownValueIsPreservedOnFailure() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let cpuReader = QueueingReader<CPUSnapshot>(
            results: [
                .available(CPUSnapshot(timestamp: .zero, utilization: 0.75, logicalCoreCount: 8)),
                .unavailable(.temporarilyUnavailable)
            ]
        )
        let engine = MetricsEngine(
            cpuReader: cpuReader,
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        let first = await engine.currentSnapshot()
        #expect(first.cpu?.availability == .available)
        #expect(first.cpu?.utilization == 0.75)

        await fastScheduler.advance()
        await fastScheduler.waitUntilIntervalsCount(2)
        let second = await engine.currentSnapshot()
        #expect(second.cpu?.availability == .unavailable(.temporarilyUnavailable))
        #expect(second.cpu?.utilization == 0.75)
        #expect(second.cpu?.logicalCoreCount == 8)

        await engine.stop()
    }

    @Test("Temperature reads merge into the snapshot on the slow loop and record the hottest of CPU/GPU in history")
    func temperatureMergesAndRecordsHottestInHistory() async {
        // Temperature rides the fast loop but samples on its own floored cadence, so this drives
        // the fast scheduler and advances the clock past that floor between ticks.
        let clock = SteppingClock()
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let temperatureReader = QueueingReader<TemperatureSnapshot>(
            results: [
                .available(TemperatureSnapshot(timestamp: .zero, cpuCelsius: 52, gpuCelsius: 46)),
                .unavailable(.unsupported)
            ]
        )
        let engine = MetricsEngine(
            cpuReader: QueueingReader(results: [.available(CPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            temperatureReader: temperatureReader,
            clock: clock,
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        let first = await engine.currentSnapshot()
        #expect(first.temperature?.availability == .available)
        #expect(first.temperature?.cpuCelsius == 52)
        #expect(first.temperature?.gpuCelsius == 46)
        #expect(await engine.history(for: .temperatureHottestCelsius).map(\.value) == [52])

        await clock.advance(by: CadencePolicy.temperatureMinimumInterval)
        await fastScheduler.advance()
        await fastScheduler.waitUntilIntervalsCount(2)
        let second = await engine.currentSnapshot()
        #expect(second.temperature?.availability == .unavailable(.unsupported))
        #expect(second.temperature?.cpuCelsius == 52)
        #expect(second.temperature?.gpuCelsius == 46)
        #expect(await engine.history(for: .temperatureHottestCelsius).map(\.value) == [52])

        await engine.stop()
    }

    @Test("Temperature skips fast ticks that fall inside its own cadence")
    func temperatureSamplesOnItsOwnCadenceWithinTheFastLoop() async {
        // At the 1 s refresh rate the fast loop ticks every second, but temperature is floored
        // to `temperatureMinimumInterval`, so it must skip roughly every other tick rather than
        // paying nine SMC round trips each time.
        let clock = SteppingClock()
        let fastScheduler = StepScheduler()
        let temperatureReader = QueueingReader<TemperatureSnapshot>(
            results: Array(
                repeating: .available(TemperatureSnapshot(timestamp: .zero, cpuCelsius: 52, gpuCelsius: 46)),
                count: 10
            )
        )
        let engine = MetricsEngine(
            cpuReader: QueueingReader(results: Array(repeating: .available(CPUSnapshot(timestamp: .zero, utilization: 0.1)), count: 10)),
            memoryReader: QueueingReader(results: Array(repeating: .available(MemorySnapshot(timestamp: .zero, usedBytes: 1)), count: 10)),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: Array(repeating: .available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1)), count: 10)),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: Array(repeating: .available(GPUSnapshot(timestamp: .zero, utilization: 0.1)), count: 10)),
            temperatureReader: temperatureReader,
            clock: clock,
            fastScheduler: fastScheduler,
            slowScheduler: StepScheduler()
        )

        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        // The first tick is always due.
        #expect(await temperatureReader.callCount == 1)

        // One second later the fast loop ticks again, but temperature is not yet due.
        await clock.advance(by: 1)
        await fastScheduler.advance()
        await fastScheduler.waitUntilIntervalsCount(2)
        #expect(await temperatureReader.callCount == 1)

        // Two seconds in, it is.
        await clock.advance(by: 1)
        await fastScheduler.advance()
        await fastScheduler.waitUntilIntervalsCount(3)
        #expect(await temperatureReader.callCount == 2)

        await engine.stop()
    }

    @Test("Snapshots publish in order and history stays bounded")
    func snapshotsPublishInOrderWithBoundedHistory() async {
        let clock = SteppingClock()
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let cpuReader = SteppingCPUReader()
        let engine = MetricsEngine(
            cpuReader: cpuReader,
            memoryReader: QueueingReader(results: Array(repeating: .available(MemorySnapshot(timestamp: .zero, usedBytes: 1)), count: 10)),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: Array(repeating: .available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1)), count: 10)),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: Array(repeating: .available(GPUSnapshot(timestamp: .zero, utilization: 0.1)), count: 10)),
            // Stubbed explicitly: temperature now samples inside the fast loop, and the default
            // reader would put a real multi-millisecond SMC round trip into this timing-sensitive
            // test.
            temperatureReader: QueueingReader(
                results: Array(repeating: .unavailable(.unsupported), count: 10)
            ),
            clock: clock,
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler,
            historyRetention: 3,
            historyCapacity: 3
        )

        var iterator = await engine.snapshots().makeAsyncIterator()
        await engine.start()

        var timestamps: [TimeInterval] = []
        let tickCount = 5
        for i in 0..<tickCount {
            await fastScheduler.waitUntilIntervalsCount(i + 1)
            if let snapshot = await iterator.next() {
                timestamps.append(snapshot.timestamp.monotonicSeconds)
            }
            // Deliberately not released after the final tick: `advance()` frees a loop iteration
            // that nothing then waits for, so a trailing one would race the assertions below and
            // could slip an extra sample into the bounded history.
            if i < tickCount - 1 {
                await clock.advance(by: 1)
                await fastScheduler.advance()
            }
        }

        #expect(timestamps == timestamps.sorted())
        #expect(Set(timestamps).count == timestamps.count)

        let history = await engine.history(for: .cpuUtilization)
        #expect(history.map(\.value) == [2.0, 3.0, 4.0])

        await engine.stop()
    }

    @Test("No polling task leaks after cancellation")
    func noPollingTaskLeaksAfterCancellation() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let cpuReader = QueueingReader<CPUSnapshot>(
            results: Array(repeating: .available(CPUSnapshot(timestamp: .zero, utilization: 0.1)), count: 20)
        )
        let engine = MetricsEngine(
            cpuReader: cpuReader,
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        let callCountBeforeStop = await cpuReader.callCount

        await engine.stop()
        // stop() cancels the suspended loop task; the cancellation handler resolves
        // its pending wait automatically. Give the runtime a moment to unwind it.
        try? await Task.sleep(nanoseconds: 30_000_000)

        #expect(await cpuReader.callCount == callCountBeforeStop)
    }

    @Test("setActiveMetrics restricts the fast loop to reading only active metrics")
    func setActiveMetricsRestrictsFastLoopReads() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let cpuReader = QueueingReader<CPUSnapshot>(
            results: [.available(CPUSnapshot(timestamp: .zero, utilization: 0.4))]
        )
        let memoryReader = QueueingReader<MemorySnapshot>(
            results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]
        )
        let networkReader = QueueingReader<NetworkSnapshot>(
            results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]
        )
        let gpuReader = QueueingReader<GPUSnapshot>(
            results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]
        )
        let engine = MetricsEngine(
            cpuReader: cpuReader,
            memoryReader: memoryReader,
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: networkReader,
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: gpuReader,
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        await engine.setActiveMetrics([.cpu, .memory])
        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)

        #expect(await cpuReader.callCount == 1)
        #expect(await memoryReader.callCount == 1)
        #expect(await networkReader.callCount == 0)
        #expect(await gpuReader.callCount == 0)

        let snapshot = await engine.currentSnapshot()
        #expect(snapshot.cpu?.utilization == 0.4)
        #expect(snapshot.network == nil)
        #expect(snapshot.gpu == nil)

        await engine.stop()
    }

    @Test("setActiveMetrics restricts the slow loop to reading only active metrics")
    func setActiveMetricsRestrictsSlowLoopReads() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let storageReader = QueueingReader<StorageSnapshot>(
            results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]
        )
        let batteryReader = QueueingReader<BatterySnapshot>(
            results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]
        )
        let temperatureReader = QueueingReader<TemperatureSnapshot>(
            results: [.available(TemperatureSnapshot(timestamp: .zero, cpuCelsius: 40, gpuCelsius: 38))]
        )
        let engine = MetricsEngine(
            cpuReader: QueueingReader(results: [.available(CPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: storageReader,
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: batteryReader,
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            temperatureReader: temperatureReader,
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        await engine.setActiveMetrics([.storage])
        await engine.start()
        await slowScheduler.waitUntilIntervalsCount(1)

        #expect(await storageReader.callCount == 1)
        #expect(await batteryReader.callCount == 0)
        #expect(await temperatureReader.callCount == 0)

        let snapshot = await engine.currentSnapshot()
        #expect(snapshot.storage != nil)
        #expect(snapshot.battery == nil)
        #expect(snapshot.temperature == nil)
        #expect(await engine.history(for: .temperatureHottestCelsius).isEmpty)

        await engine.stop()
    }

    @Test("MetricsEngine samples all six metrics within a reasonable time budget")
    func samplingCostStaysWithinBudget() async {
        let fastScheduler = StepScheduler()
        let slowScheduler = StepScheduler()
        let engine = MetricsEngine(
            cpuReader: QueueingReader(results: [.available(CPUSnapshot(timestamp: .zero, utilization: 0.5))]),
            memoryReader: QueueingReader(results: [.available(MemorySnapshot(timestamp: .zero, usedBytes: 1))]),
            storageReader: QueueingReader(results: [.available(StorageSnapshot(timestamp: .zero, usedBytes: 1))]),
            networkReader: QueueingReader(results: [.available(NetworkSnapshot(timestamp: .zero, downloadBytesPerSecond: 1))]),
            batteryReader: QueueingReader(results: [.available(BatterySnapshot(timestamp: .zero, percentage: 1))]),
            gpuReader: QueueingReader(results: [.available(GPUSnapshot(timestamp: .zero, utilization: 0.1))]),
            fastScheduler: fastScheduler,
            slowScheduler: slowScheduler
        )

        let start = DispatchTime.now()
        await engine.start()
        await fastScheduler.waitUntilIntervalsCount(1)
        await slowScheduler.waitUntilIntervalsCount(1)
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        #expect(elapsedSeconds < 1.0)

        await engine.stop()
    }
}

private actor QueueingReader<Snapshot: MetricSnapshot>: MetricReader {
    private var results: [MetricResult<Snapshot>]
    private(set) var callCount = 0

    init(results: [MetricResult<Snapshot>]) {
        self.results = results
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<Snapshot> {
        callCount += 1
        guard !results.isEmpty else {
            return .unavailable(.noData)
        }
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

extension QueueingReader: CPUReader where Snapshot == CPUSnapshot {}
extension QueueingReader: MemoryReader where Snapshot == MemorySnapshot {}
extension QueueingReader: StorageReader where Snapshot == StorageSnapshot {}
extension QueueingReader: NetworkReader where Snapshot == NetworkSnapshot {}
extension QueueingReader: BatteryReader where Snapshot == BatterySnapshot {}
extension QueueingReader: GPUReader where Snapshot == GPUSnapshot {}
extension QueueingReader: TemperatureReader where Snapshot == TemperatureSnapshot {}

private actor SteppingClock: MetricClock {
    private nonisolated(unsafe) var current = MetricTimestamp.zero

    nonisolated func now() -> MetricTimestamp {
        current
    }

    func advance(by seconds: TimeInterval) {
        current = current.advanced(by: seconds)
    }
}

private actor SteppingCPUReader: CPUReader {
    func read(at timestamp: MetricTimestamp) async -> MetricResult<CPUSnapshot> {
        .available(CPUSnapshot(timestamp: timestamp, utilization: timestamp.monotonicSeconds))
    }
}

/// A `MetricScheduler` whose `wait(for:)` suspends until the test explicitly
/// releases it via `advance()`/`stop()`, making polling-loop progress deterministic.
/// Cancellation is honored immediately so a cancelled loop's pending wait never leaks.
private actor StepScheduler: MetricScheduler {
    private struct PendingWait {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var pending: [PendingWait] = []
    private(set) var requestedIntervals: [TimeInterval] = []

    func wait(for interval: TimeInterval) async throws {
        requestedIntervals.append(interval)
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append(PendingWait(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelPendingWait(id) }
        }
    }

    private func cancelPendingWait(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    func advance() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().continuation.resume()
    }

    func stop() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().continuation.resume(throwing: CancellationError())
    }

    func waitUntilIntervalsCount(_ count: Int) async {
        while requestedIntervals.count < count {
            await Task.yield()
        }
    }
}

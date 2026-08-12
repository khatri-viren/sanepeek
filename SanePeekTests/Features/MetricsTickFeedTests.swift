import Foundation
import Testing
@testable import SanePeek

@MainActor
struct MetricsTickFeedTests {

    @Test("Fixture feed emits deterministic baseline values and one sample for every series")
    func fixtureFeedEmitsCompleteFirstTick() async {
        let baseline = MetricFixtures.baseline()
        let feed = FixtureMetricsTickFeed(interval: 0, baseline: baseline)
        let stream = feed.ticks()
        var iterator = stream.makeAsyncIterator()

        guard let tick = await iterator.next() else {
            Issue.record("Expected the fixture feed to emit an initial tick")
            return
        }

        #expect(tick.snapshot.timestamp == baseline.timestamp)
        #expect(tick.snapshot.cpu == baseline.cpu)
        #expect(tick.snapshot.memory == baseline.memory)
        #expect(tick.snapshot.storage == baseline.storage)
        #expect(tick.snapshot.battery == baseline.battery)
        #expect(tick.snapshot.gpu == baseline.gpu)
        #expect(tick.snapshot.temperature == baseline.temperature)
        // Upload starts with its deliberate phase shift so fixture charts do not move in lockstep.
        #expect(tick.snapshot.network?.downloadBytesPerSecond == 12_000_000)
        #expect(tick.snapshot.network?.uploadBytesPerSecond == 2_800_000)
        #expect(tick.cpuHistory == [0.38])
        #expect(tick.cpuUserHistory == [0.28])
        #expect(tick.cpuSystemHistory == [0.10])
        #expect(tick.memoryHistory == [8_589_934_592])
        #expect(tick.memoryAppHistory == [0.375])
        #expect(tick.memoryWiredHistory == [0.075])
        #expect(tick.memoryCompressedHistory == [0.05])
        #expect(tick.networkDownloadHistory == [12_000_000])
        #expect(tick.networkUploadHistory == [2_800_000])
        #expect(tick.gpuHistory == [0.22])
        #expect(tick.temperatureHistory == [52])
    }

    @Test("Live feed maps every history series from one coherent engine observation")
    func liveFeedMapsEveryHistorySeries() async {
        let timestamp = MetricTimestamp.zero
        let engine = MetricsEngine(
            cpuReader: FeedReader(result: .available(CPUSnapshot(timestamp: timestamp, utilization: 0.38, userUtilization: 0.28, systemUtilization: 0.10))),
            memoryReader: FeedReader(result: .available(MemorySnapshot(timestamp: timestamp, usedBytes: 100, appUtilization: 0.30, wiredUtilization: 0.06, compressedUtilization: 0.04))),
            storageReader: FeedReader(result: .available(StorageSnapshot(timestamp: timestamp, usedBytes: 200))),
            networkReader: FeedReader(result: .available(NetworkSnapshot(timestamp: timestamp, downloadBytesPerSecond: 300, uploadBytesPerSecond: 40))),
            batteryReader: FeedReader(result: .available(BatterySnapshot(timestamp: timestamp, percentage: 0.8))),
            gpuReader: FeedReader(result: .available(GPUSnapshot(timestamp: timestamp, utilization: 0.22))),
            temperatureReader: FeedReader(result: .available(TemperatureSnapshot(timestamp: timestamp, cpuCelsius: 52, gpuCelsius: 46))),
            clock: TestMetricClock(startingAt: timestamp),
            fastScheduler: FeedSuspendingScheduler(),
            slowScheduler: FeedSuspendingScheduler()
        )
        let feed = LiveMetricsTickFeed(engine: engine)
        let stream = feed.ticks()
        var iterator = stream.makeAsyncIterator()

        await engine.start()
        guard let tick = await iterator.next() else {
            Issue.record("Expected the live feed to emit an engine observation")
            await engine.stop()
            return
        }

        #expect(tick.snapshot.cpu?.utilization == 0.38)
        #expect(tick.snapshot.memory?.usedBytes == 100)
        #expect(tick.snapshot.network?.downloadBytesPerSecond == 300)
        #expect(tick.snapshot.gpu?.utilization == 0.22)
        #expect(tick.snapshot.temperature?.cpuCelsius == 52)
        #expect(tick.cpuHistory == [0.38])
        #expect(tick.cpuUserHistory == [0.28])
        #expect(tick.cpuSystemHistory == [0.10])
        #expect(tick.memoryHistory == [100])
        #expect(tick.memoryAppHistory == [0.30])
        #expect(tick.memoryWiredHistory == [0.06])
        #expect(tick.memoryCompressedHistory == [0.04])
        #expect(tick.networkDownloadHistory == [300])
        #expect(tick.networkUploadHistory == [40])
        #expect(tick.gpuHistory == [0.22])
        #expect(tick.temperatureHistory == [52])

        await engine.stop()
    }
}

private actor FeedReader<Snapshot: MetricSnapshot>: MetricReader {
    let result: MetricResult<Snapshot>

    init(result: MetricResult<Snapshot>) {
        self.result = result
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<Snapshot> {
        result
    }
}

extension FeedReader: CPUReader where Snapshot == CPUSnapshot {}
extension FeedReader: MemoryReader where Snapshot == MemorySnapshot {}
extension FeedReader: StorageReader where Snapshot == StorageSnapshot {}
extension FeedReader: NetworkReader where Snapshot == NetworkSnapshot {}
extension FeedReader: BatteryReader where Snapshot == BatterySnapshot {}
extension FeedReader: GPUReader where Snapshot == GPUSnapshot {}
extension FeedReader: TemperatureReader where Snapshot == TemperatureSnapshot {}

private actor FeedSuspendingScheduler: MetricScheduler {
    func wait(for interval: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

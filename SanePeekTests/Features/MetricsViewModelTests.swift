import Foundation
import Observation
import Testing

@testable import SanePeek

@Suite("MetricsViewModel")
@MainActor
struct MetricsViewModelTests {

    @Test("The view model starts with placeholders and marks the first tick as data")
    func startsEmptyThenAppliesFirstTick() async {
        let feed = TestMetricsTickFeed()
        let viewModel = MetricsViewModel(feed: feed)

        #expect(viewModel.hasReceivedData == false)
        #expect(viewModel.cpuCard.primaryValue == "--")
        #expect(viewModel.cards.isEmpty)

        let tick = Self.tick(snapshot: MetricFixtures.baseline())
        feed.send(tick)

        while !viewModel.hasReceivedData {
            await Task.yield()
        }

        #expect(viewModel.hasReceivedData)
        #expect(viewModel.cpuCard.primaryValue == "38%")
        #expect(viewModel.cards.map(\.id) == [.storage, .battery, .gpu])
    }

    @Test("A tick populates all seven metric lookups and preserves detail histories")
    func mapsAllMetricCardsAndDetails() async {
        let feed = TestMetricsTickFeed()
        let viewModel = MetricsViewModel(feed: feed)
        let snapshot = MetricFixtures.baseline()
        let tick = MetricsTick(
            snapshot: snapshot,
            cpuHistory: [0.30, 0.38],
            cpuUserHistory: [0.20, 0.28],
            cpuSystemHistory: [0.10, 0.10],
            memoryHistory: [8_000, 8_589_934_592],
            memoryAppHistory: [0.30, 0.375],
            memoryWiredHistory: [0.06, 0.075],
            memoryCompressedHistory: [0.04, 0.05],
            networkDownloadHistory: [10, 12_000_000],
            networkUploadHistory: [2, 2_000_000],
            gpuHistory: [0.10, 0.22],
            temperatureHistory: [48, 52]
        )

        feed.send(tick)
        while !viewModel.hasReceivedData {
            await Task.yield()
        }

        for kind in MetricKind.allCases {
            #expect(viewModel.card(for: kind)?.id == kind)
        }

        #expect(viewModel.cpuDetail?.chipName == "Preview Processor")
        #expect(viewModel.cpuDetail?.userPercentageText == "28%")
        #expect(viewModel.cpuDetail?.systemPercentageText == "10%")
        #expect(viewModel.cpuDetail?.idlePercentageText == "62%")
        #expect(viewModel.cpuDetail?.userHistory == [0.20, 0.28])
        #expect(viewModel.cpuDetail?.systemHistory == [0.10, 0.10])

        #expect(viewModel.memoryDetail?.totalRAMText == "17.2 GB")
        #expect(viewModel.memoryDetail?.appHistory == [0.30, 0.375])
        #expect(viewModel.memoryDetail?.wiredHistory == [0.06, 0.075])
        #expect(viewModel.memoryDetail?.compressedHistory == [0.04, 0.05])

        #expect(viewModel.temperatureDetail?.hottestCelsius == 52)
        #expect(viewModel.temperatureDetail?.hottestText == "52 °C")
        #expect(viewModel.temperatureDetail?.cpuText == "52 °C")
        #expect(viewModel.temperatureDetail?.gpuText == "46 °C")

        #expect(viewModel.networkDetail?.subtitleText == "en0")
        #expect(viewModel.networkDetail?.downloadText == "12 MB/s")
        #expect(viewModel.networkDetail?.uploadText == "2 MB/s")
        #expect(viewModel.networkDetail?.downloadHistory == [10, 12_000_000])
        #expect(viewModel.networkDetail?.uploadHistory == [2, 2_000_000])

        #expect(viewModel.card(for: .storage)?.storageUsageDetail?.usedText == "256 GB")
        #expect(viewModel.card(for: .storage)?.storageUsageDetail?.freeText == "744 GB")
    }

    @Test("Unavailable snapshots keep placeholders, hide unreliable GPU, and clear details")
    func mapsUnavailableStateSafely() async {
        let feed = TestMetricsTickFeed()
        let viewModel = MetricsViewModel(feed: feed)

        feed.send(Self.tick(snapshot: MetricFixtures.unavailable()))
        while !viewModel.hasReceivedData {
            await Task.yield()
        }

        #expect(viewModel.cpuCard.primaryValue == "--")
        #expect(viewModel.cpuCard.unavailableMessage == "This metric is temporarily unavailable.")
        #expect(viewModel.memoryCard.primaryValue == "--")
        #expect(viewModel.networkCard.primaryValue == "--")
        #expect(viewModel.temperatureCard.primaryValue == "--")
        #expect(viewModel.cpuDetail == nil)
        #expect(viewModel.memoryDetail == nil)
        #expect(viewModel.temperatureDetail == nil)
        #expect(viewModel.networkDetail == nil)
        #expect(viewModel.card(for: .gpu) == nil)
        #expect(viewModel.cards.map(\.id) == [.storage, .battery])
        #expect(viewModel.card(for: .storage)?.unavailableMessage == "No data is available yet.")
        #expect(viewModel.card(for: .battery)?.unavailableMessage == "This metric is not applicable.")
    }

    @Test("Applying an identical tick does not invalidate an observed card")
    func identicalTickIsAnObservationNoOp() async {
        let feed = TestMetricsTickFeed()
        let viewModel = MetricsViewModel(feed: feed)
        let baselineTick = Self.tick(snapshot: MetricFixtures.baseline())
        let warningTick = Self.tick(snapshot: MetricFixtures.warning())

        feed.send(baselineTick)
        while !viewModel.hasReceivedData {
            await Task.yield()
        }

        feed.send(warningTick)
        while viewModel.cpuCard.primaryValue != "82%" {
            await Task.yield()
        }

        let changes = ObservationChangeCounter()
        withObservationTracking {
            _ = viewModel.cpuCard
        } onChange: {
            changes.increment()
        }

        feed.send(warningTick)
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(changes.value == 0)
    }

    @Test("Releasing the view model cancels its feed consumer")
    func releasingViewModelCancelsConsumer() async {
        let feed = CancellationTrackingFeed()
        weak var weakViewModel: MetricsViewModel?

        do {
            let viewModel = MetricsViewModel(feed: feed)
            weakViewModel = viewModel

            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(1))
            while !feed.didEnter, clock.now < deadline {
                await Task.yield()
            }
            #expect(feed.didEnter)
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while weakViewModel != nil, clock.now < deadline {
            await Task.yield()
        }

        #expect(weakViewModel == nil)
        while !feed.didTerminate, clock.now < deadline {
            await Task.yield()
        }
        #expect(feed.didTerminate)
    }

    @Test("The injected formatter controls card presentation")
    func usesInjectedFormatter() async {
        let feed = TestMetricsTickFeed()
        let viewModel = MetricsViewModel(
            feed: feed,
            formatterProvider: { MetricFormatter(byteUnitSystem: .binary, temperatureUnit: .fahrenheit) }
        )

        feed.send(Self.tick(snapshot: MetricFixtures.baseline()))
        while !viewModel.hasReceivedData {
            await Task.yield()
        }

        #expect(viewModel.card(for: .storage)?.storageUsageDetail?.usedText == "238 GiB")
        #expect(viewModel.temperatureDetail?.hottestText == "125.6 °F")
    }

    private static func tick(snapshot: MetricsSnapshot) -> MetricsTick {
        MetricsTick(
            snapshot: snapshot,
            cpuHistory: [snapshot.cpu?.utilization].compactMap { $0 },
            cpuUserHistory: [snapshot.cpu?.userUtilization].compactMap { $0 },
            cpuSystemHistory: [snapshot.cpu?.systemUtilization].compactMap { $0 },
            memoryHistory: [snapshot.memory?.usedBytes].compactMap { $0.map(Double.init) },
            memoryAppHistory: [snapshot.memory?.appUtilization].compactMap { $0 },
            memoryWiredHistory: [snapshot.memory?.wiredUtilization].compactMap { $0 },
            memoryCompressedHistory: [snapshot.memory?.compressedUtilization].compactMap { $0 },
            networkDownloadHistory: [snapshot.network?.downloadBytesPerSecond].compactMap { $0 },
            networkUploadHistory: [snapshot.network?.uploadBytesPerSecond].compactMap { $0 },
            gpuHistory: [snapshot.gpu?.utilization].compactMap { $0 },
            temperatureHistory: [
                [snapshot.temperature?.cpuCelsius, snapshot.temperature?.gpuCelsius]
                    .compactMap { $0 }
                    .max()
            ].compactMap { $0 }
        )
    }
}

private final class ObservationChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

@MainActor
private final class CancellationTrackingFeed: MetricsTickFeed {
    private let stream: AsyncStream<MetricsTick>
    private let probe: TerminationProbe

    init() {
        let probe = TerminationProbe()
        self.probe = probe
        self.stream = AsyncStream { continuation in
            continuation.onTermination = { _ in
                probe.mark()
            }
        }
    }

    var didTerminate: Bool {
        probe.value
    }

    var didEnter: Bool {
        probe.enteredValue
    }

    func ticks() -> AsyncStream<MetricsTick> {
        probe.markEntered()
        return stream
    }
}

private final class TerminationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false
    private var entered = false

    var value: Bool {
        lock.withLock { terminated }
    }

    var enteredValue: Bool {
        lock.withLock { entered }
    }

    func markEntered() {
        lock.withLock { entered = true }
    }

    func mark() {
        lock.withLock { terminated = true }
    }
}

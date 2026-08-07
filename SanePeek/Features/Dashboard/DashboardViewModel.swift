import Observation

/// Exposes presentation-ready card state to `DashboardView`. Consumes
/// whichever `DashboardTickFeed` it's handed — fixture-backed for previews
/// and UI tests, `LiveDashboardTickFeed` for `.live` runtime.
@MainActor
@Observable
final class DashboardViewModel {
    private(set) var cpuCard = MetricCardMapping.cpuCard(nil, history: [])
    private(set) var cpuDetail: CPUCardDetail?
    private(set) var memoryCard = MetricCardMapping.memoryCard(nil, history: [])
    private(set) var memoryDetail: MemoryCardDetail?
    private(set) var temperatureCard = MetricCardMapping.temperatureCard(nil, history: [])
    private(set) var temperatureDetail: TemperatureCardDetail?
    private(set) var networkCard = MetricCardMapping.networkCard(nil, history: [])
    private(set) var networkDetail: NetworkCardDetail?
    private(set) var cards: [MetricCardModel] = []
    private(set) var hasReceivedData = false

    private let feed: any DashboardTickFeed
    private let formatterProvider: @MainActor () -> MetricFormatter
    @ObservationIgnored
    private nonisolated(unsafe) var consumeTask: Task<Void, Never>?

    init(feed: any DashboardTickFeed, formatterProvider: @escaping @MainActor () -> MetricFormatter = { MetricFormatter() }) {
        self.feed = feed
        self.formatterProvider = formatterProvider
        start()
    }

    deinit {
        consumeTask?.cancel()
    }

    private func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await tick in self.feed.ticks() {
                self.apply(tick)
            }
        }
    }

    private func apply(_ tick: DashboardTick) {
        let snapshot = tick.snapshot
        let formatter = formatterProvider()

        cpuCard = MetricCardMapping.cpuCard(snapshot.cpu, history: tick.cpuHistory, formatter: formatter)
        cpuDetail = MetricCardMapping.cpuDetail(
            snapshot.cpu,
            userHistory: tick.cpuUserHistory,
            systemHistory: tick.cpuSystemHistory,
            formatter: formatter
        )

        memoryCard = MetricCardMapping.memoryCard(snapshot.memory, history: tick.memoryHistory, formatter: formatter)
        memoryDetail = MetricCardMapping.memoryDetail(
            snapshot.memory,
            appHistory: tick.memoryAppHistory,
            wiredHistory: tick.memoryWiredHistory,
            compressedHistory: tick.memoryCompressedHistory,
            formatter: formatter
        )

        temperatureCard = MetricCardMapping.temperatureCard(snapshot.temperature, history: tick.temperatureHistory, formatter: formatter)
        temperatureDetail = MetricCardMapping.temperatureDetail(snapshot.temperature, formatter: formatter)

        networkCard = MetricCardMapping.networkCard(snapshot.network, history: tick.networkDownloadHistory, formatter: formatter)
        networkDetail = MetricCardMapping.networkDetail(
            snapshot.network,
            downloadHistory: tick.networkDownloadHistory,
            uploadHistory: tick.networkUploadHistory,
            formatter: formatter
        )

        var next: [MetricCardModel] = [
            MetricCardMapping.storageCard(snapshot.storage, formatter: formatter),
            MetricCardMapping.batteryCard(snapshot.battery, formatter: formatter)
        ]

        if let gpuCard = MetricCardMapping.gpuCard(snapshot.gpu, history: tick.gpuHistory, formatter: formatter) {
            next.append(gpuCard)
        }

        cards = next
        hasReceivedData = true
    }

    /// Looks up the current card for any metric, regardless of whether it's one of the four
    /// dedicated hero cards or one of the generic `cards` entries — used by the menu bar and
    /// its popup, which address metrics by `MetricKind` rather than by dedicated property.
    func card(for kind: MetricKind) -> MetricCardModel? {
        switch kind {
        case .cpu: cpuCard
        case .memory: memoryCard
        case .temperature: temperatureCard
        case .network: networkCard
        case .storage, .battery, .gpu: cards.first { $0.id == kind }
        }
    }
}

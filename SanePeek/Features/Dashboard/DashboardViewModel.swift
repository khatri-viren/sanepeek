import Observation

/// Exposes presentation-ready card state to `DashboardView`. Consumes
/// whichever `DashboardTickFeed` it's handed — fixture-backed for previews
/// and UI tests, `LiveDashboardTickFeed` for `.live` runtime.
@MainActor
@Observable
final class DashboardViewModel {
    private(set) var cards: [MetricCardModel] = []

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

        var next: [MetricCardModel] = [
            MetricCardMapping.cpuCard(snapshot.cpu, history: tick.cpuHistory, formatter: formatter),
            MetricCardMapping.memoryCard(snapshot.memory, history: tick.memoryHistory, formatter: formatter),
            MetricCardMapping.storageCard(snapshot.storage, formatter: formatter),
            MetricCardMapping.networkCard(snapshot.network, history: tick.networkDownloadHistory, formatter: formatter),
            MetricCardMapping.batteryCard(snapshot.battery, formatter: formatter)
        ]

        if let gpuCard = MetricCardMapping.gpuCard(snapshot.gpu, history: tick.gpuHistory, formatter: formatter) {
            next.append(gpuCard)
        }

        cards = next
    }
}

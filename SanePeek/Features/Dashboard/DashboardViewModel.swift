import Observation

/// Exposes presentation-ready card state to `DashboardView`. Owns its own
/// fixture feed for now — Phase 5 decides how a live engine gets wired in.
@MainActor
@Observable
final class DashboardViewModel {
    private(set) var cards: [MetricCardModel] = []

    private let feed: FixtureDashboardTickFeed
    @ObservationIgnored
    private nonisolated(unsafe) var consumeTask: Task<Void, Never>?

    init(feed: FixtureDashboardTickFeed) {
        self.feed = feed
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

        var next: [MetricCardModel] = [
            MetricCardMapping.cpuCard(snapshot.cpu, history: tick.cpuHistory),
            MetricCardMapping.memoryCard(snapshot.memory, history: tick.memoryHistory),
            MetricCardMapping.storageCard(snapshot.storage),
            MetricCardMapping.networkCard(snapshot.network, history: tick.networkDownloadHistory),
            MetricCardMapping.batteryCard(snapshot.battery)
        ]

        if let gpuCard = MetricCardMapping.gpuCard(snapshot.gpu, history: tick.gpuHistory) {
            next.append(gpuCard)
        }

        cards = next
    }
}

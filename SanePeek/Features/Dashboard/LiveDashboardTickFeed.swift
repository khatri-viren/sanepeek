/// Bridges a live `MetricsEngine` into the dashboard's `DashboardTick` shape,
/// pairing each published snapshot with the bounded histories the engine
/// already tracks for CPU, memory, network download, and GPU.
@MainActor
final class LiveDashboardTickFeed: DashboardTickFeed {
    private let engine: MetricsEngine

    init(engine: MetricsEngine) {
        self.engine = engine
    }

    func ticks() -> AsyncStream<DashboardTick> {
        AsyncStream { continuation in
            let engine = engine
            let task = Task {
                await engine.start()

                for await snapshot in await engine.snapshots() {
                    async let cpuHistory = engine.history(for: .cpuUtilization)
                    async let memoryHistory = engine.history(for: .memoryUsedBytes)
                    async let networkDownloadHistory = engine.history(for: .networkDownloadBytesPerSecond)
                    async let gpuHistory = engine.history(for: .gpuUtilization)

                    continuation.yield(
                        DashboardTick(
                            snapshot: snapshot,
                            cpuHistory: await cpuHistory.map(\.value),
                            memoryHistory: await memoryHistory.map(\.value),
                            networkDownloadHistory: await networkDownloadHistory.map(\.value),
                            gpuHistory: await gpuHistory.map(\.value)
                        )
                    )
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await engine.stop() }
            }
        }
    }
}

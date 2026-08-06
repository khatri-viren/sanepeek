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
                    async let cpuUserHistory = engine.history(for: .cpuUserUtilization)
                    async let cpuSystemHistory = engine.history(for: .cpuSystemUtilization)
                    async let memoryHistory = engine.history(for: .memoryUsedBytes)
                    async let memoryAppHistory = engine.history(for: .memoryAppUtilization)
                    async let memoryWiredHistory = engine.history(for: .memoryWiredUtilization)
                    async let memoryCompressedHistory = engine.history(for: .memoryCompressedUtilization)
                    async let networkDownloadHistory = engine.history(for: .networkDownloadBytesPerSecond)
                    async let networkUploadHistory = engine.history(for: .networkUploadBytesPerSecond)
                    async let gpuHistory = engine.history(for: .gpuUtilization)
                    async let temperatureHistory = engine.history(for: .temperatureHottestCelsius)

                    continuation.yield(
                        DashboardTick(
                            snapshot: snapshot,
                            cpuHistory: await cpuHistory.map(\.value),
                            cpuUserHistory: await cpuUserHistory.map(\.value),
                            cpuSystemHistory: await cpuSystemHistory.map(\.value),
                            memoryHistory: await memoryHistory.map(\.value),
                            memoryAppHistory: await memoryAppHistory.map(\.value),
                            memoryWiredHistory: await memoryWiredHistory.map(\.value),
                            memoryCompressedHistory: await memoryCompressedHistory.map(\.value),
                            networkDownloadHistory: await networkDownloadHistory.map(\.value),
                            networkUploadHistory: await networkUploadHistory.map(\.value),
                            gpuHistory: await gpuHistory.map(\.value),
                            temperatureHistory: await temperatureHistory.map(\.value)
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

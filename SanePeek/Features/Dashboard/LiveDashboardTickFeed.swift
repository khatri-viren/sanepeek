/// Bridges coherent `MetricsEngine` observations into the dashboard's `DashboardTick` shape.
/// Snapshot and histories arrive together; this adapter only performs semantic field mapping.
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
                let observations = await engine.observations()
                await engine.start()

                for await observation in observations {
                    continuation.yield(
                        DashboardTick(
                            snapshot: observation.snapshot,
                            cpuHistory: observation.history(for: .cpuUtilization).map(\.value),
                            cpuUserHistory: observation.history(for: .cpuUserUtilization).map(\.value),
                            cpuSystemHistory: observation.history(for: .cpuSystemUtilization).map(\.value),
                            memoryHistory: observation.history(for: .memoryUsedBytes).map(\.value),
                            memoryAppHistory: observation.history(for: .memoryAppUtilization).map(\.value),
                            memoryWiredHistory: observation.history(for: .memoryWiredUtilization).map(\.value),
                            memoryCompressedHistory: observation.history(for: .memoryCompressedUtilization).map(\.value),
                            networkDownloadHistory: observation.history(for: .networkDownloadBytesPerSecond).map(\.value),
                            networkUploadHistory: observation.history(for: .networkUploadBytesPerSecond).map(\.value),
                            gpuHistory: observation.history(for: .gpuUtilization).map(\.value),
                            temperatureHistory: observation.history(for: .temperatureHottestCelsius).map(\.value)
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

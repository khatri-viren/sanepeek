import Foundation

/// Ticks a baseline snapshot forward deterministically (sine-based variation,
/// not randomness) so the fixture-driven dashboard has something to animate
/// before Phase 5 wires in the real engine.
@MainActor
final class FixtureDashboardTickFeed {
    private let interval: TimeInterval
    private let baseline: MetricsSnapshot
    private static let historyLimit = 60

    init(interval: TimeInterval = 1, baseline: MetricsSnapshot) {
        self.interval = interval
        self.baseline = baseline
    }

    func ticks() -> AsyncStream<DashboardTick> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var tickIndex = 0
                var cpuHistory: [Double] = []
                var memoryHistory: [Double] = []
                var networkDownloadHistory: [Double] = []
                var gpuHistory: [Double] = []

                while !Task.isCancelled {
                    let snapshot = Self.varying(self.baseline, tickIndex: tickIndex)

                    if let utilization = snapshot.cpu?.utilization {
                        cpuHistory = Self.appending(cpuHistory, utilization)
                    }
                    if let used = snapshot.memory?.usedBytes {
                        memoryHistory = Self.appending(memoryHistory, Double(used))
                    }
                    if let download = snapshot.network?.downloadBytesPerSecond {
                        networkDownloadHistory = Self.appending(networkDownloadHistory, download)
                    }
                    if let utilization = snapshot.gpu?.utilization {
                        gpuHistory = Self.appending(gpuHistory, utilization)
                    }

                    continuation.yield(
                        DashboardTick(
                            snapshot: snapshot,
                            cpuHistory: cpuHistory,
                            memoryHistory: memoryHistory,
                            networkDownloadHistory: networkDownloadHistory,
                            gpuHistory: gpuHistory
                        )
                    )

                    tickIndex += 1
                    try? await Task.sleep(for: .seconds(self.interval))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func appending(_ history: [Double], _ value: Double) -> [Double] {
        var next = history
        next.append(value)
        if next.count > historyLimit {
            next.removeFirst(next.count - historyLimit)
        }
        return next
    }

    private static func varying(_ baseline: MetricsSnapshot, tickIndex: Int) -> MetricsSnapshot {
        let wave = sin(Double(tickIndex) / 6)
        let timestamp = baseline.timestamp.advanced(by: Double(tickIndex))

        let cpu = baseline.cpu.map { snapshot in
            CPUSnapshot(
                timestamp: timestamp,
                availability: snapshot.availability,
                utilization: snapshot.utilization.map { clampFraction($0 + wave * 0.15) },
                logicalCoreCount: snapshot.logicalCoreCount,
                performanceCoreCount: snapshot.performanceCoreCount,
                efficiencyCoreCount: snapshot.efficiencyCoreCount
            )
        }

        let network = baseline.network.map { snapshot in
            NetworkSnapshot(
                timestamp: timestamp,
                availability: snapshot.availability,
                downloadBytesPerSecond: snapshot.downloadBytesPerSecond.map { max(0, $0 * (1 + wave * 0.4)) },
                uploadBytesPerSecond: snapshot.uploadBytesPerSecond,
                connectivity: snapshot.connectivity,
                interfaceNames: snapshot.interfaceNames
            )
        }

        let gpu = baseline.gpu.map { snapshot in
            GPUSnapshot(
                timestamp: timestamp,
                availability: snapshot.availability,
                utilization: snapshot.utilization.map { clampFraction($0 + wave * 0.1) },
                name: snapshot.name
            )
        }

        let memory = baseline.memory.map { snapshot -> MemorySnapshot in
            var usedBytes = snapshot.usedBytes
            var availableBytes = snapshot.availableBytes
            if let used = snapshot.usedBytes, let available = snapshot.availableBytes {
                let total = Double(used) + Double(available)
                let jitteredUsed = clampFraction(Double(used) / total + wave * 0.05) * total
                usedBytes = UInt64(jitteredUsed)
                availableBytes = UInt64(total - jitteredUsed)
            }
            return MemorySnapshot(
                timestamp: timestamp,
                availability: snapshot.availability,
                usedBytes: usedBytes,
                availableBytes: availableBytes,
                pressure: snapshot.pressure
            )
        }

        let storage = baseline.storage.map { snapshot in
            StorageSnapshot(
                timestamp: timestamp,
                availability: snapshot.availability,
                usedBytes: snapshot.usedBytes,
                availableBytes: snapshot.availableBytes,
                totalBytes: snapshot.totalBytes
            )
        }

        let battery = baseline.battery.map { snapshot in
            BatterySnapshot(
                timestamp: timestamp,
                availability: snapshot.availability,
                percentage: snapshot.percentage,
                chargingState: snapshot.chargingState,
                timeRemaining: snapshot.timeRemaining,
                healthPercentage: snapshot.healthPercentage
            )
        }

        return MetricsSnapshot(
            timestamp: timestamp,
            cpu: cpu,
            memory: memory,
            storage: storage,
            network: network,
            battery: battery,
            gpu: gpu,
            hardware: baseline.hardware
        )
    }

    private static func clampFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

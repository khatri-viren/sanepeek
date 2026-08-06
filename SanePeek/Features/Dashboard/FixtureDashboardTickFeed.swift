import Foundation

/// Ticks a baseline snapshot forward deterministically (sine-based variation,
/// not randomness) so preview and fixture-driven UI-test runs have something
/// to animate. `LiveDashboardTickFeed` is the equivalent for `.live` runtime.
@MainActor
final class FixtureDashboardTickFeed: DashboardTickFeed {
    private let interval: TimeInterval
    private let baseline: MetricsSnapshot
    private static let historyLimit = 60

    /// App/Wired/Compressed shares of the used-memory fraction, matching
    /// `MetricFixtures`'s split. Sum to 1 so the breakdown always accounts for the whole
    /// used fraction.
    private static let memoryAppShare = 0.75
    private static let memoryWiredShare = 0.15
    private static let memoryCompressedShare = 0.10

    init(interval: TimeInterval = 1, baseline: MetricsSnapshot) {
        self.interval = interval
        self.baseline = baseline
    }

    func ticks() -> AsyncStream<DashboardTick> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var tickIndex = 0
                var cpuHistory: [Double] = []
                var cpuUserHistory: [Double] = []
                var cpuSystemHistory: [Double] = []
                var memoryHistory: [Double] = []
                var memoryAppHistory: [Double] = []
                var memoryWiredHistory: [Double] = []
                var memoryCompressedHistory: [Double] = []
                var networkDownloadHistory: [Double] = []
                var gpuHistory: [Double] = []

                while !Task.isCancelled {
                    let snapshot = Self.varying(self.baseline, tickIndex: tickIndex)

                    if let utilization = snapshot.cpu?.utilization {
                        cpuHistory = Self.appending(cpuHistory, utilization)
                    }
                    if let userUtilization = snapshot.cpu?.userUtilization {
                        cpuUserHistory = Self.appending(cpuUserHistory, userUtilization)
                    }
                    if let systemUtilization = snapshot.cpu?.systemUtilization {
                        cpuSystemHistory = Self.appending(cpuSystemHistory, systemUtilization)
                    }
                    if let used = snapshot.memory?.usedBytes {
                        memoryHistory = Self.appending(memoryHistory, Double(used))
                    }
                    if let appUtilization = snapshot.memory?.appUtilization {
                        memoryAppHistory = Self.appending(memoryAppHistory, appUtilization)
                    }
                    if let wiredUtilization = snapshot.memory?.wiredUtilization {
                        memoryWiredHistory = Self.appending(memoryWiredHistory, wiredUtilization)
                    }
                    if let compressedUtilization = snapshot.memory?.compressedUtilization {
                        memoryCompressedHistory = Self.appending(memoryCompressedHistory, compressedUtilization)
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
                            cpuUserHistory: cpuUserHistory,
                            cpuSystemHistory: cpuSystemHistory,
                            memoryHistory: memoryHistory,
                            memoryAppHistory: memoryAppHistory,
                            memoryWiredHistory: memoryWiredHistory,
                            memoryCompressedHistory: memoryCompressedHistory,
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

        let cpu = baseline.cpu.map { snapshot -> CPUSnapshot in
            let newUtilization = snapshot.utilization.map { clampFraction($0 + wave * 0.15) }
            let scale: Double = {
                guard let oldUtilization = snapshot.utilization, oldUtilization > 0, let newUtilization else { return 1 }
                return newUtilization / oldUtilization
            }()

            return CPUSnapshot(
                timestamp: timestamp,
                availability: snapshot.availability,
                utilization: newUtilization,
                userUtilization: snapshot.userUtilization.map { clampFraction($0 * scale) },
                systemUtilization: snapshot.systemUtilization.map { clampFraction($0 * scale) },
                logicalCoreCount: snapshot.logicalCoreCount,
                performanceCoreCount: snapshot.performanceCoreCount,
                efficiencyCoreCount: snapshot.efficiencyCoreCount,
                chipName: snapshot.chipName
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
            var appUtilization = snapshot.appUtilization
            var wiredUtilization = snapshot.wiredUtilization
            var compressedUtilization = snapshot.compressedUtilization
            if let used = snapshot.usedBytes, let available = snapshot.availableBytes {
                let total = Double(used) + Double(available)
                let jitteredUsedFraction = clampFraction(Double(used) / total + wave * 0.05)
                let jitteredUsed = jitteredUsedFraction * total
                usedBytes = UInt64(jitteredUsed)
                availableBytes = UInt64(total - jitteredUsed)
                // Fixed App/Wired/Compressed shares of the jittered used fraction, so the
                // breakdown moves in sync with `usedBytes` without needing independent jitter.
                appUtilization = jitteredUsedFraction * Self.memoryAppShare
                wiredUtilization = jitteredUsedFraction * Self.memoryWiredShare
                compressedUtilization = jitteredUsedFraction * Self.memoryCompressedShare
            }
            return MemorySnapshot(
                timestamp: timestamp,
                availability: snapshot.availability,
                usedBytes: usedBytes,
                availableBytes: availableBytes,
                pressure: snapshot.pressure,
                appUtilization: appUtilization,
                wiredUtilization: wiredUtilization,
                compressedUtilization: compressedUtilization
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

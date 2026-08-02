nonisolated enum MetricFixtures {
    static func dashboard(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            cpu: CPUSnapshot(
                timestamp: timestamp,
                utilization: 0.38,
                logicalCoreCount: 10,
                performanceCoreCount: 6,
                efficiencyCoreCount: 4
            ),
            memory: MemorySnapshot(
                timestamp: timestamp,
                usedBytes: 8_589_934_592,
                availableBytes: 8_589_934_592,
                pressure: .normal
            ),
            storage: StorageSnapshot(
                timestamp: timestamp,
                usedBytes: 256_000_000_000,
                availableBytes: 744_000_000_000,
                totalBytes: 1_000_000_000_000
            ),
            network: NetworkSnapshot(
                timestamp: timestamp,
                downloadBytesPerSecond: 12_000_000,
                uploadBytesPerSecond: 2_000_000,
                connectivity: .connected,
                interfaceNames: ["en0"]
            ),
            battery: BatterySnapshot(
                timestamp: timestamp,
                percentage: 0.84,
                chargingState: .charging,
                timeRemaining: 7_200,
                healthPercentage: 0.96
            ),
            gpu: GPUSnapshot(
                timestamp: timestamp,
                utilization: 0.22,
                name: "Preview GPU"
            )
        )
    }

    static func warning(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            cpu: CPUSnapshot(
                timestamp: timestamp,
                utilization: 0.82,
                logicalCoreCount: 10,
                performanceCoreCount: 6,
                efficiencyCoreCount: 4
            ),
            memory: MemorySnapshot(
                timestamp: timestamp,
                usedBytes: 14_500_000_000,
                availableBytes: 2_500_000_000,
                pressure: .warning
            ),
            storage: StorageSnapshot(
                timestamp: timestamp,
                usedBytes: 870_000_000_000,
                availableBytes: 130_000_000_000,
                totalBytes: 1_000_000_000_000
            ),
            network: NetworkSnapshot(
                timestamp: timestamp,
                downloadBytesPerSecond: 4_000_000,
                uploadBytesPerSecond: 1_000_000,
                connectivity: .connected,
                interfaceNames: ["en0"]
            ),
            battery: BatterySnapshot(
                timestamp: timestamp,
                percentage: 0.18,
                chargingState: .unplugged,
                timeRemaining: 1_200,
                healthPercentage: 0.88
            ),
            gpu: GPUSnapshot(
                timestamp: timestamp,
                utilization: 0.55,
                name: "Preview GPU"
            )
        )
    }

    static func critical(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            cpu: CPUSnapshot(
                timestamp: timestamp,
                utilization: 0.97,
                logicalCoreCount: 10,
                performanceCoreCount: 6,
                efficiencyCoreCount: 4
            ),
            memory: MemorySnapshot(
                timestamp: timestamp,
                usedBytes: 15_800_000_000,
                availableBytes: 200_000_000,
                pressure: .critical
            ),
            storage: StorageSnapshot(
                timestamp: timestamp,
                usedBytes: 970_000_000_000,
                availableBytes: 30_000_000_000,
                totalBytes: 1_000_000_000_000
            ),
            network: NetworkSnapshot(
                timestamp: timestamp,
                downloadBytesPerSecond: 500_000,
                uploadBytesPerSecond: 100_000,
                connectivity: .connected,
                interfaceNames: ["en0"]
            ),
            battery: BatterySnapshot(
                timestamp: timestamp,
                percentage: 0.05,
                chargingState: .unplugged,
                timeRemaining: 300,
                healthPercentage: 0.72
            ),
            gpu: GPUSnapshot(
                timestamp: timestamp,
                utilization: 0.91,
                name: "Preview GPU"
            )
        )
    }

    static func unavailable(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            cpu: .unavailable(at: timestamp, reason: .temporarilyUnavailable),
            memory: .unavailable(at: timestamp, reason: .temporarilyUnavailable),
            storage: .unavailable(at: timestamp, reason: .noData),
            network: .unavailable(at: timestamp, reason: .temporarilyUnavailable),
            battery: .unavailable(at: timestamp, reason: .notApplicable),
            gpu: .unavailable(at: timestamp, reason: .unsupported)
        )
    }

    /// Otherwise-healthy dashboard where only the GPU is unavailable, matching
    /// most real Macs (no reliable IOAccelerator utilization counter). Used to
    /// verify the GPU card hides while its five siblings stay visible.
    static func gpuUnsupported(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        let baseline = dashboard(at: timestamp)
        return MetricsSnapshot(
            timestamp: timestamp,
            cpu: baseline.cpu,
            memory: baseline.memory,
            storage: baseline.storage,
            network: baseline.network,
            battery: baseline.battery,
            gpu: .unavailable(at: timestamp, reason: .unsupported)
        )
    }

    /// Mixed health: CPU and Memory stay healthy while Storage and Network
    /// report failures, so a UI test can assert both states render
    /// side by side without either masking the other.
    static func mixedFailure(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        let baseline = dashboard(at: timestamp)
        return MetricsSnapshot(
            timestamp: timestamp,
            cpu: baseline.cpu,
            memory: baseline.memory,
            storage: .unavailable(at: timestamp, reason: .noData),
            network: .unavailable(at: timestamp, reason: .temporarilyUnavailable),
            battery: baseline.battery,
            gpu: baseline.gpu
        )
    }
}

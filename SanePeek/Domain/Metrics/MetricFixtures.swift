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
}

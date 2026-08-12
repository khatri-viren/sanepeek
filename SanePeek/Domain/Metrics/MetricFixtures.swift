nonisolated enum MetricFixtures {
    static func baseline(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            cpu: CPUSnapshot(
                timestamp: timestamp,
                utilization: 0.38,
                userUtilization: 0.28,
                systemUtilization: 0.10,
                logicalCoreCount: 10,
                performanceCoreCount: 6,
                efficiencyCoreCount: 4,
                chipName: "Preview Processor"
            ),
            memory: MemorySnapshot(
                timestamp: timestamp,
                usedBytes: 8_589_934_592,
                availableBytes: 8_589_934_592,
                pressure: .normal,
                appUtilization: 0.375,
                wiredUtilization: 0.075,
                compressedUtilization: 0.05
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
                interfaceNames: ["en0"],
                primaryInterfaceName: "en0"
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
            ),
            temperature: TemperatureSnapshot(
                timestamp: timestamp,
                cpuCelsius: 52,
                gpuCelsius: 46
            )
        )
    }

    static func warning(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            cpu: CPUSnapshot(
                timestamp: timestamp,
                utilization: 0.82,
                userUtilization: 0.60,
                systemUtilization: 0.22,
                logicalCoreCount: 10,
                performanceCoreCount: 6,
                efficiencyCoreCount: 4,
                chipName: "Preview Processor"
            ),
            memory: MemorySnapshot(
                timestamp: timestamp,
                usedBytes: 14_500_000_000,
                availableBytes: 2_500_000_000,
                pressure: .warning,
                appUtilization: 0.6397,
                wiredUtilization: 0.1279,
                compressedUtilization: 0.0853
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
                interfaceNames: ["en0"],
                primaryInterfaceName: "en0"
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
            ),
            temperature: TemperatureSnapshot(
                timestamp: timestamp,
                cpuCelsius: 82,
                gpuCelsius: 74
            )
        )
    }

    static func critical(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            cpu: CPUSnapshot(
                timestamp: timestamp,
                utilization: 0.97,
                userUtilization: 0.75,
                systemUtilization: 0.22,
                logicalCoreCount: 10,
                performanceCoreCount: 6,
                efficiencyCoreCount: 4,
                chipName: "Preview Processor"
            ),
            memory: MemorySnapshot(
                timestamp: timestamp,
                usedBytes: 15_800_000_000,
                availableBytes: 200_000_000,
                pressure: .critical,
                appUtilization: 0.7406,
                wiredUtilization: 0.1481,
                compressedUtilization: 0.0988
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
                interfaceNames: ["en0"],
                primaryInterfaceName: "en0"
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
            ),
            temperature: TemperatureSnapshot(
                timestamp: timestamp,
                cpuCelsius: 97,
                gpuCelsius: 90
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
            gpu: .unavailable(at: timestamp, reason: .unsupported),
            temperature: .unavailable(at: timestamp, reason: .temporarilyUnavailable)
        )
    }

    /// Otherwise-healthy baseline where only the GPU is unavailable, matching
    /// most real Macs (no reliable IOAccelerator utilization counter). Used to
    /// verify the GPU card hides while its five siblings stay visible.
    static func gpuUnsupported(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        let baseline = baseline(at: timestamp)
        return MetricsSnapshot(
            timestamp: timestamp,
            cpu: baseline.cpu,
            memory: baseline.memory,
            storage: baseline.storage,
            network: baseline.network,
            battery: baseline.battery,
            gpu: .unavailable(at: timestamp, reason: .unsupported),
            temperature: baseline.temperature
        )
    }

    /// Mixed health: CPU and Memory stay healthy while Storage and Network
    /// report failures, so a UI test can assert both states render
    /// side by side without either masking the other.
    static func mixedFailure(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        let baseline = baseline(at: timestamp)
        return MetricsSnapshot(
            timestamp: timestamp,
            cpu: baseline.cpu,
            memory: baseline.memory,
            storage: .unavailable(at: timestamp, reason: .noData),
            network: .unavailable(at: timestamp, reason: .temporarilyUnavailable),
            battery: baseline.battery,
            gpu: baseline.gpu,
            temperature: baseline.temperature
        )
    }

    /// No longer what the live app shows — `SMCTemperatureAdapter` reads real die
    /// temperatures in the direct-download build. This fixture stays because that path is
    /// unavailable in a sandboxed build and on Macs that expose no readable sensor, and the
    /// "not supported on this Mac" card state still has to render correctly rather than
    /// showing stale or misleading numbers.
    static func temperatureUnsupported(at timestamp: MetricTimestamp = .zero) -> MetricsSnapshot {
        let baseline = baseline(at: timestamp)
        return MetricsSnapshot(
            timestamp: timestamp,
            cpu: baseline.cpu,
            memory: baseline.memory,
            storage: baseline.storage,
            network: baseline.network,
            battery: baseline.battery,
            gpu: baseline.gpu,
            temperature: .unavailable(at: timestamp, reason: .unsupported)
        )
    }
}

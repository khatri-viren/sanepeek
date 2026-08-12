import Testing

@testable import SanePeek

@Suite("Reader failure propagation")
struct ReaderFailurePropagationTests {
    private let failure = MetricFailure(kind: .systemUnavailable)

    @Test("CPU reader preserves adapter failures")
    func cpuPreservesFailure() async {
        let reader = LiveCPUReader(adapter: FailingCPUAdapter(result: .failed(failure)))

        #expect((await reader.read(at: .zero)).availability == .failed(failure))
    }

    @Test("CPU reader preserves adapter unavailability")
    func cpuPreservesUnavailability() async {
        let reader = LiveCPUReader(adapter: FailingCPUAdapter(result: .unavailable(.temporarilyUnavailable)))

        #expect((await reader.read(at: .zero)).availability == .unavailable(.temporarilyUnavailable))
    }

    @Test("Memory reader preserves adapter failures")
    func memoryPreservesFailure() async {
        let reader = LiveMemoryReader(
            adapter: FailingMemoryAdapter(result: .failed(failure)),
            pressureSource: NoopMemoryPressureSource()
        )

        #expect((await reader.read(at: .zero)).availability == .failed(failure))
    }

    @Test("Memory reader preserves adapter unavailability")
    func memoryPreservesUnavailability() async {
        let reader = LiveMemoryReader(
            adapter: FailingMemoryAdapter(result: .unavailable(.temporarilyUnavailable)),
            pressureSource: NoopMemoryPressureSource()
        )

        #expect((await reader.read(at: .zero)).availability == .unavailable(.temporarilyUnavailable))
    }

    @Test("Storage reader preserves adapter failures")
    func storagePreservesFailure() async {
        let reader = LiveStorageReader(adapter: FailingStorageAdapter(result: .failed(failure)))

        #expect((await reader.read(at: .zero)).availability == .failed(failure))
    }

    @Test("Storage reader preserves adapter unavailability")
    func storagePreservesUnavailability() async {
        let reader = LiveStorageReader(
            adapter: FailingStorageAdapter(result: .unavailable(.temporarilyUnavailable))
        )

        #expect((await reader.read(at: .zero)).availability == .unavailable(.temporarilyUnavailable))
    }

    @Test("Network reader preserves adapter failures")
    func networkPreservesFailure() async {
        let reader = LiveNetworkReader(adapter: FailingNetworkAdapter(result: .failed(failure)))

        #expect((await reader.read(at: .zero)).availability == .failed(failure))
    }

    @Test("Network reader preserves adapter unavailability")
    func networkPreservesUnavailability() async {
        let reader = LiveNetworkReader(
            adapter: FailingNetworkAdapter(result: .unavailable(.temporarilyUnavailable))
        )

        #expect((await reader.read(at: .zero)).availability == .unavailable(.temporarilyUnavailable))
    }

    @Test("Battery reader preserves adapter failures")
    func batteryPreservesFailure() async {
        let reader = LiveBatteryReader(adapter: FailingBatteryAdapter(result: .failed(failure)))

        #expect((await reader.read(at: .zero)).availability == .failed(failure))
    }

    @Test("Battery reader preserves adapter unavailability")
    func batteryPreservesUnavailability() async {
        let reader = LiveBatteryReader(
            adapter: FailingBatteryAdapter(result: .unavailable(.temporarilyUnavailable))
        )

        #expect((await reader.read(at: .zero)).availability == .unavailable(.temporarilyUnavailable))
    }

    @Test("GPU reader preserves adapter failures")
    func gpuPreservesFailure() async {
        let reader = LiveGPUReader(
            adapter: FailingGPUAdapter(
                capability: GPUCapability(isSupported: true),
                result: .failed(failure)
            )
        )

        #expect((await reader.read(at: .zero)).availability == .failed(failure))
    }

    @Test("GPU reader preserves adapter unavailability")
    func gpuPreservesUnavailability() async {
        let reader = LiveGPUReader(
            adapter: FailingGPUAdapter(
                capability: GPUCapability(isSupported: true),
                result: .unavailable(.temporarilyUnavailable)
            )
        )

        #expect((await reader.read(at: .zero)).availability == .unavailable(.temporarilyUnavailable))
    }

    @Test("Temperature reader preserves adapter failures")
    func temperaturePreservesFailure() async {
        let reader = LiveTemperatureReader(
            adapter: FailingTemperatureAdapter(isSupported: true, result: .failed(failure))
        )

        #expect((await reader.read(at: .zero)).availability == .failed(failure))
    }

    @Test("Temperature reader preserves adapter unavailability")
    func temperaturePreservesUnavailability() async {
        let reader = LiveTemperatureReader(
            adapter: FailingTemperatureAdapter(
                isSupported: true,
                result: .unavailable(.temporarilyUnavailable)
            )
        )

        #expect((await reader.read(at: .zero)).availability == .unavailable(.temporarilyUnavailable))
    }
}

private struct FailingCPUAdapter: CPUSystemAdapter {
    let result: MetricResult<CPUSystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<CPUSystemSample> { result }
}

private struct FailingMemoryAdapter: MemorySystemAdapter {
    let result: MetricResult<MemorySystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<MemorySystemSample> { result }
}

private struct NoopMemoryPressureSource: MemoryPressureSource {
    var currentPressure: MemoryPressure? { nil }

    func start() {}
    func cancel() {}
}

private struct FailingStorageAdapter: StorageSystemAdapter {
    let result: MetricResult<StorageSystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<StorageSystemSample> { result }
}

private struct FailingNetworkAdapter: NetworkSystemAdapter {
    let result: MetricResult<NetworkSystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<NetworkSystemSample> { result }
}

private struct FailingBatteryAdapter: BatterySystemAdapter {
    let result: MetricResult<BatterySystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<BatterySystemSample> { result }
}

private struct FailingGPUAdapter: GPUSystemAdapter {
    let capability: GPUCapability
    let result: MetricResult<GPUSystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<GPUSystemSample> { result }
}

private struct FailingTemperatureAdapter: TemperatureSystemAdapter {
    let isSupported: Bool
    let result: MetricResult<TemperatureSystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<TemperatureSystemSample> { result }
}

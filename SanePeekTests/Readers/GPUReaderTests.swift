import Testing

@testable import SanePeek

@Suite("GPU reader")
struct GPUReaderTests {
    @Test("Reads the live IORegistry utilization when the GPU exposes it")
    func readsLiveIORegistryUtilization() {
        let adapter = IORegistryGPUAdapter()
        guard adapter.capability.isSupported else {
            return
        }

        guard case let .available(sample) = adapter.read(at: .zero) else {
            Issue.record("The GPU advertised utilization support but did not return a sample")
            return
        }

        #expect(sample.utilization != nil)
        #expect(sample.utilization.map { (0...1).contains($0) } == true)
    }

    @Test("Converts IORegistry utilization percentages into normalized samples")
    func convertsUtilizationPercentage() {
        #expect(IORegistryGPUAdapter.utilizationFraction(fromPercent: 0) == 0)
        #expect(IORegistryGPUAdapter.utilizationFraction(fromPercent: 58) == 0.58)
        #expect(IORegistryGPUAdapter.utilizationFraction(fromPercent: 100) == 1)
    }

    @Test("Rejects invalid IORegistry utilization percentages")
    func rejectsInvalidUtilizationPercentage() {
        #expect(IORegistryGPUAdapter.utilizationFraction(fromPercent: -1) == nil)
        #expect(IORegistryGPUAdapter.utilizationFraction(fromPercent: 101) == nil)
        #expect(IORegistryGPUAdapter.utilizationFraction(fromPercent: .infinity) == nil)
    }

    @Test("Preserves an optional utilization while falling back to capability name")
    func preservesOptionalUtilizationAndCapabilityName() async {
        let reader = LiveGPUReader(
            adapter: OptionalGPUAdapter(
                capability: GPUCapability(isSupported: true, name: "Fixture GPU"),
                result: .available(GPUSystemSample(utilization: nil, name: nil))
            )
        )

        let result = await reader.read(at: .zero)

        guard case let .available(snapshot) = result else {
            Issue.record("Expected an available GPU snapshot, got \(result)")
            return
        }

        #expect(snapshot.utilization == nil)
        #expect(snapshot.name == "Fixture GPU")
    }
}

private struct OptionalGPUAdapter: GPUSystemAdapter {
    let capability: GPUCapability
    let result: MetricResult<GPUSystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<GPUSystemSample> { result }
}

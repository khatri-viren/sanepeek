import Testing

@testable import SanePeek

@Suite("GPU reader")
struct GPUReaderTests {
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

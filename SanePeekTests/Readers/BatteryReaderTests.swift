import Testing

@testable import SanePeek

@Suite("Battery reader")
struct BatteryReaderTests {
    @Test("Rejects impossible capacity relationships as invalid data")
    func rejectsImpossibleCapacityRelationships() async {
        let reader = LiveBatteryReader(
            adapter: FixtureBatteryAdapter(
                result: .available(
                    BatterySystemSample(
                        isPresent: true,
                        currentCapacity: 101,
                        maximumCapacity: 100,
                        isCharging: false,
                        timeToEmptyMinutes: 30,
                        timeToFullChargeMinutes: nil,
                        designCapacity: 100
                    )
                )
            )
        )

        let result = await reader.read(at: .zero)

        #expect(result.availability == .failed(MetricFailure(kind: .invalidData)))
    }
}

private struct FixtureBatteryAdapter: BatterySystemAdapter {
    let result: MetricResult<BatterySystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<BatterySystemSample> {
        result
    }
}

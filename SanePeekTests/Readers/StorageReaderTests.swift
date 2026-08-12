import Testing

@testable import SanePeek

@Suite("Storage reader")
struct StorageReaderTests {
    @Test("Reports no data when the system omits volume capacity")
    func reportsNoDataForMissingCapacity() async {
        let reader = LiveStorageReader(
            adapter: FixtureStorageAdapter(
                result: .available(StorageSystemSample(totalBytes: nil, availableBytes: nil))
            )
        )

        let result = await reader.read(at: .zero)

        #expect(result.availability == .unavailable(.noData))
    }
}

private struct FixtureStorageAdapter: StorageSystemAdapter {
    let result: MetricResult<StorageSystemSample>

    func read(at timestamp: MetricTimestamp) -> MetricResult<StorageSystemSample> {
        result
    }
}

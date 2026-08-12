import Testing

@testable import SanePeek

@Suite("Memory domain")
struct MemoryDomainTests {
    @Test("Memory byte conversion reports overflow as invalid data")
    func byteConversionReportsOverflow() {
        let result = MemoryByteConverter.bytes(from: UInt64.max, pageSize: 2)

        #expect(result.availability == .failed(MetricFailure(kind: .invalidData)))
    }
}

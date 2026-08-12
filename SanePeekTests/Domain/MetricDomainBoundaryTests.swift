import Testing

@testable import SanePeek

@Suite("Metric domain boundaries")
struct MetricDomainBoundaryTests {
    @Test("A backwards counter without a maximum is unavailable")
    func backwardsCounterWithoutMaximumIsUnavailable() {
        let result = MetricCounterDeltaCalculator.calculate(from: 10, to: 2)

        #expect(result.availability == .unavailable(.noData))
    }

    @Test("A rollover counter outside its declared maximum is invalid")
    func rolloverOutsideMaximumIsInvalid() {
        let result = MetricCounterDeltaCalculator.calculate(from: 101, to: 2, counterMaximum: 100)

        #expect(result.availability == .failed(MetricFailure(kind: .invalidData)))
    }

    @Test("Every unavailable reason has a user-facing message")
    func unavailableReasonsHaveMessages() {
        let reasons: [MetricUnavailableReason] = [
            .unsupported,
            .notPresent,
            .noData,
            .temporarilyUnavailable,
            .notApplicable
        ]

        for reason in reasons {
            #expect(!reason.userMessage.isEmpty)
            #expect(MetricAvailability.unavailable(reason).userMessage == reason.userMessage)
        }
    }

    @Test("A sample at the same timestamp replaces the previous ring-buffer value")
    func sameTimestampReplacesPreviousValue() {
        var history = MetricRingBuffer<Double>(retention: 60, capacity: 2)

        _ = history.append(MetricSample(timestamp: .zero, value: 1))
        _ = history.append(MetricSample(timestamp: .zero, value: 2))

        #expect(history.samples.map(\.value) == [2])
        #expect(history.newest?.value == 2)
    }
}

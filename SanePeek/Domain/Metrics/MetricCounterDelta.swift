nonisolated enum MetricCounterDeltaCalculator {
    static func calculate(
        from previous: UInt64,
        to current: UInt64,
        counterMaximum: UInt64? = nil
    ) -> MetricResult<UInt64> {
        if current >= previous {
            return .available(current - previous)
        }

        guard let counterMaximum else {
            return .unavailable(.noData)
        }

        guard previous <= counterMaximum, current <= counterMaximum else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (distanceToMaximum, firstOverflow) = counterMaximum
            .subtractingReportingOverflow(previous)
        guard !firstOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (wrappedDistance, secondOverflow) = distanceToMaximum
            .addingReportingOverflow(1)
        guard !secondOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (delta, thirdOverflow) = wrappedDistance.addingReportingOverflow(current)
        guard !thirdOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(delta)
    }
}

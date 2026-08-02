nonisolated struct CPUCounterSample: Sendable, Equatable {
    let timestamp: MetricTimestamp
    let userTicks: UInt64
    let systemTicks: UInt64
    let idleTicks: UInt64
    let niceTicks: UInt64

    init(
        timestamp: MetricTimestamp,
        userTicks: UInt64,
        systemTicks: UInt64,
        idleTicks: UInt64,
        niceTicks: UInt64 = 0
    ) {
        self.timestamp = timestamp
        self.userTicks = userTicks
        self.systemTicks = systemTicks
        self.idleTicks = idleTicks
        self.niceTicks = niceTicks
    }
}

nonisolated enum CPUUtilizationCalculator {
    static func calculate(
        from previous: CPUCounterSample,
        to current: CPUCounterSample,
        counterMaximum: UInt64? = nil
    ) -> MetricResult<Double> {
        let duration = current.timestamp.monotonicSeconds - previous.timestamp.monotonicSeconds
        guard duration.isFinite, duration > 0 else {
            return .unavailable(.noData)
        }

        let deltas = [
            MetricCounterDeltaCalculator.calculate(
                from: previous.userTicks,
                to: current.userTicks,
                counterMaximum: counterMaximum
            ),
            MetricCounterDeltaCalculator.calculate(
                from: previous.systemTicks,
                to: current.systemTicks,
                counterMaximum: counterMaximum
            ),
            MetricCounterDeltaCalculator.calculate(
                from: previous.idleTicks,
                to: current.idleTicks,
                counterMaximum: counterMaximum
            ),
            MetricCounterDeltaCalculator.calculate(
                from: previous.niceTicks,
                to: current.niceTicks,
                counterMaximum: counterMaximum
            )
        ]

        guard let values = availableValues(from: deltas) else {
            return unavailableOrFailed(from: deltas)
        }

        let (activeTicks, activeOverflow) = values[0]
            .addingReportingOverflow(values[1])
        guard !activeOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (activeWithNiceTicks, niceOverflow) = activeTicks
            .addingReportingOverflow(values[3])
        guard !niceOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (totalTicks, totalOverflow) = activeWithNiceTicks
            .addingReportingOverflow(values[2])
        guard !totalOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        guard totalTicks > 0 else {
            return .unavailable(.noData)
        }

        let utilization = Double(activeWithNiceTicks) / Double(totalTicks)
        guard utilization.isFinite else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(min(max(utilization, 0), 1))
    }

    private static func availableValues(
        from results: [MetricResult<UInt64>]
    ) -> [UInt64]? {
        var values: [UInt64] = []
        values.reserveCapacity(results.count)

        for result in results {
            guard case let .available(value) = result else {
                return nil
            }
            values.append(value)
        }

        return values
    }

    private static func unavailableOrFailed(
        from results: [MetricResult<UInt64>]
    ) -> MetricResult<Double> {
        for result in results {
            if case let .failed(failure) = result {
                return .failed(failure)
            }
        }
        return .unavailable(.noData)
    }
}

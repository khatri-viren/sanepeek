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

/// User/system split of one utilization sample. `user` folds in nice-priority
/// ticks (still user-mode work, just lower priority); `total` is what
/// `CPUUtilizationCalculator.calculate` alone would have returned.
nonisolated struct CPUUtilizationBreakdown: Sendable, Equatable {
    let user: Double
    let system: Double

    var total: Double {
        min(max(user + system, 0), 1)
    }
}

nonisolated enum CPUUtilizationCalculator {
    static func calculate(
        from previous: CPUCounterSample,
        to current: CPUCounterSample,
        counterMaximum: UInt64? = nil
    ) -> MetricResult<Double> {
        switch calculateBreakdown(from: previous, to: current, counterMaximum: counterMaximum) {
        case let .available(breakdown):
            .available(breakdown.total)
        case let .unavailable(reason):
            .unavailable(reason)
        case let .failed(failure):
            .failed(failure)
        }
    }

    static func calculateBreakdown(
        from previous: CPUCounterSample,
        to current: CPUCounterSample,
        counterMaximum: UInt64? = nil
    ) -> MetricResult<CPUUtilizationBreakdown> {
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
            return unavailableOrFailedBreakdown(from: deltas)
        }

        let (userWithNiceTicks, niceOverflow) = values[0]
            .addingReportingOverflow(values[3])
        guard !niceOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (activeTicks, activeOverflow) = userWithNiceTicks
            .addingReportingOverflow(values[1])
        guard !activeOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (totalTicks, totalOverflow) = activeTicks
            .addingReportingOverflow(values[2])
        guard !totalOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        guard totalTicks > 0 else {
            return .unavailable(.noData)
        }

        let userFraction = Double(userWithNiceTicks) / Double(totalTicks)
        let systemFraction = Double(values[1]) / Double(totalTicks)
        guard userFraction.isFinite, systemFraction.isFinite else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(
            CPUUtilizationBreakdown(
                user: min(max(userFraction, 0), 1),
                system: min(max(systemFraction, 0), 1)
            )
        )
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

    private static func unavailableOrFailedBreakdown(
        from results: [MetricResult<UInt64>]
    ) -> MetricResult<CPUUtilizationBreakdown> {
        for result in results {
            if case let .failed(failure) = result {
                return .failed(failure)
            }
        }
        return .unavailable(.noData)
    }
}

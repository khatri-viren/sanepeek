import Foundation

nonisolated enum BatteryChargingState: String, Equatable, Sendable {
    case charging
    case charged
    case unplugged
    case unknown
}

nonisolated struct BatterySnapshot: MetricSnapshot {
    let timestamp: MetricTimestamp
    let availability: MetricAvailability
    let percentage: Double?
    let chargingState: BatteryChargingState?
    let timeRemaining: TimeInterval?
    let healthPercentage: Double?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        percentage: Double? = nil,
        chargingState: BatteryChargingState? = nil,
        timeRemaining: TimeInterval? = nil,
        healthPercentage: Double? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.percentage = percentage
        self.chargingState = chargingState
        self.timeRemaining = timeRemaining
        self.healthPercentage = healthPercentage
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

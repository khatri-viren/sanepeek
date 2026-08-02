nonisolated struct GPUSnapshot: MetricSnapshot {
    let timestamp: MetricTimestamp
    let availability: MetricAvailability
    let utilization: Double?
    let name: String?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        utilization: Double? = nil,
        name: String? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.utilization = utilization
        self.name = name
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

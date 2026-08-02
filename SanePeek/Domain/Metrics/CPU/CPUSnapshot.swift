nonisolated struct CPUSnapshot: MetricSnapshot {
    let timestamp: MetricTimestamp
    let availability: MetricAvailability
    let utilization: Double?
    let logicalCoreCount: Int?
    let performanceCoreCount: Int?
    let efficiencyCoreCount: Int?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        utilization: Double? = nil,
        logicalCoreCount: Int? = nil,
        performanceCoreCount: Int? = nil,
        efficiencyCoreCount: Int? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.utilization = utilization
        self.logicalCoreCount = logicalCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

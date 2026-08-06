nonisolated struct CPUSnapshot: MetricSnapshot {
    let timestamp: MetricTimestamp
    let availability: MetricAvailability
    let utilization: Double?
    /// User-mode fraction of this sample's window, nice ticks folded in. Sums
    /// with `systemUtilization` to `utilization`.
    let userUtilization: Double?
    let systemUtilization: Double?
    let logicalCoreCount: Int?
    let performanceCoreCount: Int?
    let efficiencyCoreCount: Int?
    /// Marketing chip name (e.g. "Apple M4 Pro") from `machdep.cpu.brand_string`.
    let chipName: String?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        utilization: Double? = nil,
        userUtilization: Double? = nil,
        systemUtilization: Double? = nil,
        logicalCoreCount: Int? = nil,
        performanceCoreCount: Int? = nil,
        efficiencyCoreCount: Int? = nil,
        chipName: String? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.utilization = utilization
        self.userUtilization = userUtilization
        self.systemUtilization = systemUtilization
        self.logicalCoreCount = logicalCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
        self.chipName = chipName
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

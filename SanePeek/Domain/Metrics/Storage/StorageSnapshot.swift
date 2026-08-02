nonisolated struct StorageSnapshot: MetricSnapshot {
    let timestamp: MetricTimestamp
    let availability: MetricAvailability
    let usedBytes: UInt64?
    let availableBytes: UInt64?
    let totalBytes: UInt64?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        usedBytes: UInt64? = nil,
        availableBytes: UInt64? = nil,
        totalBytes: UInt64? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

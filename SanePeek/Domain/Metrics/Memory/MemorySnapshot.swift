nonisolated enum MemoryPressure: String, Equatable, Sendable {
    case normal
    case warning
    case critical
}

nonisolated struct MemorySnapshot: MetricSnapshot {
    let timestamp: MetricTimestamp
    let availability: MetricAvailability
    let usedBytes: UInt64?
    let availableBytes: UInt64?
    let pressure: MemoryPressure?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        usedBytes: UInt64? = nil,
        availableBytes: UInt64? = nil,
        pressure: MemoryPressure? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.pressure = pressure
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

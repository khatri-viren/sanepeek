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
    /// 0...1 fractions of total memory, mirroring `CPUSnapshot.userUtilization`/
    /// `systemUtilization`. Supplementary to `usedBytes`/`availableBytes` — nil when the
    /// breakdown can't be computed even though used/available are known.
    let appUtilization: Double?
    let wiredUtilization: Double?
    let compressedUtilization: Double?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        usedBytes: UInt64? = nil,
        availableBytes: UInt64? = nil,
        pressure: MemoryPressure? = nil,
        appUtilization: Double? = nil,
        wiredUtilization: Double? = nil,
        compressedUtilization: Double? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.pressure = pressure
        self.appUtilization = appUtilization
        self.wiredUtilization = wiredUtilization
        self.compressedUtilization = compressedUtilization
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

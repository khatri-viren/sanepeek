nonisolated struct TemperatureSnapshot: MetricSnapshot {
    let timestamp: MetricTimestamp
    let availability: MetricAvailability
    let cpuCelsius: Double?
    let gpuCelsius: Double?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        cpuCelsius: Double? = nil,
        gpuCelsius: Double? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

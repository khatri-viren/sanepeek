nonisolated enum NetworkConnectivity: String, Equatable, Sendable {
    case connected
    case disconnected
    case unknown
}

nonisolated struct NetworkSnapshot: MetricSnapshot {
    let timestamp: MetricTimestamp
    let availability: MetricAvailability
    let downloadBytesPerSecond: Double?
    let uploadBytesPerSecond: Double?
    let connectivity: NetworkConnectivity?
    let interfaceNames: [String]?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        downloadBytesPerSecond: Double? = nil,
        uploadBytesPerSecond: Double? = nil,
        connectivity: NetworkConnectivity? = nil,
        interfaceNames: [String]? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.connectivity = connectivity
        self.interfaceNames = interfaceNames
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

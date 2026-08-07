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
    /// The BSD name of the interface actually carrying the default route (e.g.
    /// "en0"), from SystemConfiguration — distinct from `interfaceNames`, which
    /// lists every "up" interface including VPN tunnels and AirDrop/Continuity
    /// virtual ones. Nil when there's no default route.
    let primaryInterfaceName: String?

    init(
        timestamp: MetricTimestamp,
        availability: MetricAvailability = .available,
        downloadBytesPerSecond: Double? = nil,
        uploadBytesPerSecond: Double? = nil,
        connectivity: NetworkConnectivity? = nil,
        interfaceNames: [String]? = nil,
        primaryInterfaceName: String? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.connectivity = connectivity
        self.interfaceNames = interfaceNames
        self.primaryInterfaceName = primaryInterfaceName
    }

    static func unavailable(
        at timestamp: MetricTimestamp,
        reason: MetricUnavailableReason
    ) -> Self {
        Self(timestamp: timestamp, availability: .unavailable(reason))
    }
}

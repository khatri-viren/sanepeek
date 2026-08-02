import Foundation

nonisolated struct MetricTimestamp: Equatable, Comparable, Sendable {
    let date: Date
    let monotonicSeconds: TimeInterval

    init(date: Date, monotonicSeconds: TimeInterval) {
        self.date = date
        self.monotonicSeconds = monotonicSeconds
    }

    static let zero = Self(
        date: Date(timeIntervalSince1970: 0),
        monotonicSeconds: 0
    )

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.monotonicSeconds < rhs.monotonicSeconds
    }

    func advanced(by seconds: TimeInterval) -> Self {
        Self(
            date: date.addingTimeInterval(seconds),
            monotonicSeconds: monotonicSeconds + seconds
        )
    }
}

nonisolated enum MetricKind: String, CaseIterable, Hashable, Sendable {
    case cpu
    case memory
    case storage
    case network
    case battery
    case gpu
}

nonisolated protocol MetricSnapshot: Sendable, Equatable {
    var timestamp: MetricTimestamp { get }
    var availability: MetricAvailability { get }
}

nonisolated enum MemoryPressure: String, Equatable, Sendable {
    case normal
    case warning
    case critical
}

nonisolated enum NetworkConnectivity: String, Equatable, Sendable {
    case connected
    case disconnected
    case unknown
}

nonisolated enum BatteryChargingState: String, Equatable, Sendable {
    case charging
    case charged
    case unplugged
    case unknown
}

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

nonisolated struct HardwareSnapshot: Sendable, Equatable {
    let timestamp: MetricTimestamp
    let modelIdentifier: String?
    let processorName: String?
    let logicalCoreCount: Int?

    init(
        timestamp: MetricTimestamp,
        modelIdentifier: String? = nil,
        processorName: String? = nil,
        logicalCoreCount: Int? = nil
    ) {
        self.timestamp = timestamp
        self.modelIdentifier = modelIdentifier
        self.processorName = processorName
        self.logicalCoreCount = logicalCoreCount
    }
}

nonisolated struct MetricsSnapshot: Sendable, Equatable {
    let timestamp: MetricTimestamp
    let cpu: CPUSnapshot?
    let memory: MemorySnapshot?
    let storage: StorageSnapshot?
    let network: NetworkSnapshot?
    let battery: BatterySnapshot?
    let gpu: GPUSnapshot?
    let hardware: HardwareSnapshot?

    init(
        timestamp: MetricTimestamp,
        cpu: CPUSnapshot? = nil,
        memory: MemorySnapshot? = nil,
        storage: StorageSnapshot? = nil,
        network: NetworkSnapshot? = nil,
        battery: BatterySnapshot? = nil,
        gpu: GPUSnapshot? = nil,
        hardware: HardwareSnapshot? = nil
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.network = network
        self.battery = battery
        self.gpu = gpu
        self.hardware = hardware
    }

    var containsAvailableMetric: Bool {
        [cpu?.availability, memory?.availability, storage?.availability, network?.availability, battery?.availability, gpu?.availability]
            .contains { $0?.isAvailable == true }
    }
}

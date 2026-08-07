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

nonisolated enum MetricKind: String, CaseIterable, Hashable, Sendable, Codable {
    case cpu
    case memory
    case storage
    case network
    case battery
    case gpu
    case temperature
}

nonisolated protocol MetricSnapshot: Sendable, Equatable {
    var timestamp: MetricTimestamp { get }
    var availability: MetricAvailability { get }
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
    let temperature: TemperatureSnapshot?
    let hardware: HardwareSnapshot?

    init(
        timestamp: MetricTimestamp,
        cpu: CPUSnapshot? = nil,
        memory: MemorySnapshot? = nil,
        storage: StorageSnapshot? = nil,
        network: NetworkSnapshot? = nil,
        battery: BatterySnapshot? = nil,
        gpu: GPUSnapshot? = nil,
        temperature: TemperatureSnapshot? = nil,
        hardware: HardwareSnapshot? = nil
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.network = network
        self.battery = battery
        self.gpu = gpu
        self.temperature = temperature
        self.hardware = hardware
    }

    var containsAvailableMetric: Bool {
        [cpu?.availability, memory?.availability, storage?.availability, network?.availability, battery?.availability, gpu?.availability, temperature?.availability]
            .contains { $0?.isAvailable == true }
    }
}

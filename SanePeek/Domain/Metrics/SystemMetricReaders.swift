import Darwin
import Foundation
import IOKit
import IOKit.ps
import Network

nonisolated struct CPUHardwareInfo: Sendable, Equatable {
    let logicalCoreCount: Int?
    let performanceCoreCount: Int?
    let efficiencyCoreCount: Int?

    init(
        logicalCoreCount: Int? = nil,
        performanceCoreCount: Int? = nil,
        efficiencyCoreCount: Int? = nil
    ) {
        self.logicalCoreCount = logicalCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
    }
}

nonisolated struct CPUSystemSample: Sendable, Equatable {
    let counter: CPUCounterSample
    let hardware: CPUHardwareInfo

    init(counter: CPUCounterSample, hardware: CPUHardwareInfo = .init()) {
        self.counter = counter
        self.hardware = hardware
    }
}

nonisolated protocol CPUSystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<CPUSystemSample>
}

actor LiveCPUReader: CPUReader {
    private let adapter: any CPUSystemAdapter
    private let counterMaximum: UInt64?
    private var previousCounter: CPUCounterSample?

    init(
        adapter: any CPUSystemAdapter = MachCPUSystemAdapter(),
        counterMaximum: UInt64? = nil
    ) {
        self.adapter = adapter
        self.counterMaximum = counterMaximum
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<CPUSnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            let utilization = previousCounter.map { previous in
                CPUUtilizationCalculator.calculate(
                    from: previous,
                    to: sample.counter,
                    counterMaximum: counterMaximum
                ).value
            } ?? nil
            previousCounter = sample.counter

            return .available(
                CPUSnapshot(
                    timestamp: timestamp,
                    utilization: utilization,
                    logicalCoreCount: sample.hardware.logicalCoreCount,
                    performanceCoreCount: sample.hardware.performanceCoreCount,
                    efficiencyCoreCount: sample.hardware.efficiencyCoreCount
                )
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            return .failed(failure)
        }
    }
}

nonisolated struct MachCPUSystemAdapter: CPUSystemAdapter {
    init() {}

    func read(at timestamp: MetricTimestamp) -> MetricResult<CPUSystemSample> {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS else {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }

        guard let processorInfo else {
            return .unavailable(.noData)
        }

        let allocatedBytes = vm_size_t(
            Int(processorInfoCount) * MemoryLayout<natural_t>.stride
        )
        defer {
            _ = vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: processorInfo)),
                allocatedBytes
            )
        }

        let ticksPerProcessor = MemoryLayout<processor_cpu_load_info_data_t>.size
            / MemoryLayout<natural_t>.size
        let availableProcessorCount = min(
            Int(processorCount),
            Int(processorInfoCount) / ticksPerProcessor
        )

        guard availableProcessorCount > 0 else {
            return .unavailable(.noData)
        }

        let aggregateCounter: CPUCounterSample? = processorInfo.withMemoryRebound(
            to: processor_cpu_load_info_data_t.self,
            capacity: availableProcessorCount
        ) { loadInfo in
            var userTicks: UInt64 = 0
            var systemTicks: UInt64 = 0
            var idleTicks: UInt64 = 0
            var niceTicks: UInt64 = 0

            for index in 0..<availableProcessorCount {
                let ticks = loadInfo[index].cpu_ticks
                let (newUserTicks, userOverflow) = userTicks.addingReportingOverflow(UInt64(ticks.0))
                let (newSystemTicks, systemOverflow) = systemTicks.addingReportingOverflow(UInt64(ticks.1))
                let (newIdleTicks, idleOverflow) = idleTicks.addingReportingOverflow(UInt64(ticks.2))
                let (newNiceTicks, niceOverflow) = niceTicks.addingReportingOverflow(UInt64(ticks.3))

                guard !userOverflow, !systemOverflow, !idleOverflow, !niceOverflow else {
                    return nil
                }

                userTicks = newUserTicks
                systemTicks = newSystemTicks
                idleTicks = newIdleTicks
                niceTicks = newNiceTicks
            }

            return CPUCounterSample(
                timestamp: timestamp,
                userTicks: userTicks,
                systemTicks: systemTicks,
                idleTicks: idleTicks,
                niceTicks: niceTicks
            )
        }

        guard let aggregateCounter else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let logicalCoreCount = ProcessInfo.processInfo.processorCount
        let hardware = CPUHardwareInfo(
            logicalCoreCount: logicalCoreCount > 0 ? logicalCoreCount : nil,
            performanceCoreCount: readSysctlInt32(named: "hw.perflevel0.logicalcpu"),
            efficiencyCoreCount: readSysctlInt32(named: "hw.perflevel1.logicalcpu")
        )

        return .available(CPUSystemSample(counter: aggregateCounter, hardware: hardware))
    }

    private func readSysctlInt32(named name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = name.withCString {
            sysctlbyname($0, &value, &size, nil, 0)
        }

        guard result == 0, value > 0 else {
            return nil
        }
        return Int(value)
    }
}

nonisolated struct MemorySystemSample: Sendable, Equatable {
    let pageCounts: MemoryPageCounts
    let pageSize: UInt64

    init(pageCounts: MemoryPageCounts, pageSize: UInt64) {
        self.pageCounts = pageCounts
        self.pageSize = pageSize
    }
}

nonisolated protocol MemorySystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<MemorySystemSample>
}

nonisolated protocol MemoryPressureSource: Sendable {
    var currentPressure: MemoryPressure? { get }

    func start()
    func cancel()
}

actor LiveMemoryReader: MemoryReader {
    private let adapter: any MemorySystemAdapter
    private let pressureSource: any MemoryPressureSource

    init(
        adapter: any MemorySystemAdapter = MachMemorySystemAdapter(),
        pressureSource: any MemoryPressureSource = DispatchMemoryPressureSource()
    ) {
        self.adapter = adapter
        self.pressureSource = pressureSource
        pressureSource.start()
    }

    deinit {
        pressureSource.cancel()
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<MemorySnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            return MemoryByteConverter.snapshot(
                from: sample.pageCounts,
                pageSize: sample.pageSize,
                timestamp: timestamp,
                pressure: pressureSource.currentPressure
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            return .failed(failure)
        }
    }
}

nonisolated struct MachMemorySystemAdapter: MemorySystemAdapter {
    init() {}

    func read(at timestamp: MetricTimestamp) -> MetricResult<MemorySystemSample> {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }

        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    info,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }

        guard let usedPages = sumPages([
            UInt64(statistics.active_count),
            UInt64(statistics.inactive_count),
            UInt64(statistics.wire_count),
            UInt64(statistics.compressor_page_count)
        ]), let availablePages = sumPages([
            UInt64(statistics.free_count),
            UInt64(statistics.speculative_count)
        ]) else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(
            MemorySystemSample(
                pageCounts: MemoryPageCounts(
                    usedPages: usedPages,
                    availablePages: availablePages
                ),
                pageSize: UInt64(pageSize)
            )
        )
    }

    private func sumPages(_ values: [UInt64]) -> UInt64? {
        values.reduce(into: UInt64(0)) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            total = overflow ? UInt64.max : sum
        }
    }
}

final class DispatchMemoryPressureSource: MemoryPressureSource, @unchecked Sendable {
    private let lock = NSLock()
    private let source: DispatchSourceMemoryPressure
    private var started = false
    private var cancelled = false
    private var pressure: MemoryPressure?

    init(queue: DispatchQueue = DispatchQueue(label: "com.sanepeek.memory-pressure", qos: .utility)) {
        let pressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: queue
        )
        source = pressureSource
        pressureSource.setEventHandler { [weak self, pressureSource] in
            self?.update(pressureSource.data)
        }
        start()
    }

    var currentPressure: MemoryPressure? {
        lock.lock()
        defer { lock.unlock() }
        return pressure
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started, !cancelled else { return }
        source.resume()
        started = true
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        lock.unlock()
        source.cancel()
    }

    deinit {
        cancel()
    }

    private func update(_ event: DispatchSource.MemoryPressureEvent) {
        let nextPressure: MemoryPressure
        if event.contains(.critical) {
            nextPressure = .critical
        } else if event.contains(.warning) {
            nextPressure = .warning
        } else {
            nextPressure = .normal
        }

        lock.lock()
        pressure = nextPressure
        lock.unlock()
    }
}

nonisolated struct StorageSystemSample: Sendable, Equatable {
    let totalBytes: Int64?
    let availableBytes: Int64?

    init(totalBytes: Int64?, availableBytes: Int64?) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }
}

nonisolated protocol StorageSystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<StorageSystemSample>
}

nonisolated struct LiveStorageReader: StorageReader {
    private let adapter: any StorageSystemAdapter

    init(adapter: any StorageSystemAdapter = FoundationStorageSystemAdapter()) {
        self.adapter = adapter
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<StorageSnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            guard let totalBytes = sample.totalBytes, let availableBytes = sample.availableBytes else {
                return .unavailable(.noData)
            }
            guard totalBytes > 0, availableBytes >= 0, availableBytes <= totalBytes else {
                return .failed(MetricFailure(kind: .invalidData))
            }

            return .available(
                StorageSnapshot(
                    timestamp: timestamp,
                    usedBytes: UInt64(totalBytes - availableBytes),
                    availableBytes: UInt64(availableBytes),
                    totalBytes: UInt64(totalBytes)
                )
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            return .failed(failure)
        }
    }
}

nonisolated struct FoundationStorageSystemAdapter: StorageSystemAdapter {
    let volumeURL: URL

    init(volumeURL: URL = URL(fileURLWithPath: "/")) {
        self.volumeURL = volumeURL
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<StorageSystemSample> {
        do {
            let values = try volumeURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            return .available(
                StorageSystemSample(
                    totalBytes: values.volumeTotalCapacity.map(Int64.init),
                    availableBytes: values.volumeAvailableCapacity.map(Int64.init)
                )
            )
        } catch {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }
    }
}

nonisolated struct NetworkSystemSample: Sendable, Equatable {
    let counter: NetworkCounterSample
    let connectivity: NetworkConnectivity

    init(
        counter: NetworkCounterSample,
        connectivity: NetworkConnectivity
    ) {
        self.counter = counter
        self.connectivity = connectivity
    }
}

nonisolated protocol NetworkSystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<NetworkSystemSample>
}

actor LiveNetworkReader: NetworkReader {
    private let adapter: any NetworkSystemAdapter
    private let counterMaximum: UInt64?
    private var previousCounter: NetworkCounterSample?

    init(
        adapter: any NetworkSystemAdapter = DarwinNetworkSystemAdapter(),
        counterMaximum: UInt64? = nil
    ) {
        self.adapter = adapter
        self.counterMaximum = counterMaximum
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<NetworkSnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            let throughput = previousCounter.flatMap { previous in
                NetworkThroughputCalculator.calculate(
                    from: previous,
                    to: sample.counter,
                    counterMaximum: counterMaximum
                ).value
            }
            previousCounter = sample.counter

            let interfaceNames = sample.counter.interfaces
                .filter { $0.isValid && !$0.isLoopback && !$0.name.isEmpty }
                .map(\.name)
                .sorted()

            return .available(
                NetworkSnapshot(
                    timestamp: timestamp,
                    downloadBytesPerSecond: throughput?.downloadBytesPerSecond,
                    uploadBytesPerSecond: throughput?.uploadBytesPerSecond,
                    connectivity: sample.connectivity,
                    interfaceNames: interfaceNames
                )
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            return .failed(failure)
        }
    }
}

nonisolated protocol NetworkConnectivitySource: Sendable {
    var connectivity: NetworkConnectivity { get }

    func start()
    func cancel()
}

nonisolated struct DarwinNetworkSystemAdapter: NetworkSystemAdapter {
    private let connectivitySource: any NetworkConnectivitySource

    init(
        connectivitySource: any NetworkConnectivitySource = NWPathConnectivitySource()
    ) {
        self.connectivitySource = connectivitySource
        connectivitySource.start()
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<NetworkSystemSample> {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0 else {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }
        defer {
            if let addressList {
                freeifaddrs(addressList)
            }
        }

        var interfaces: [NetworkInterfaceCounter] = []
        var seenNames = Set<String>()
        var currentAddress = addressList

        while let address = currentAddress {
            let interface = address.pointee
            currentAddress = interface.ifa_next

            guard let namePointer = interface.ifa_name else {
                continue
            }

            let name = String(cString: namePointer)
            guard !name.isEmpty, seenNames.insert(name).inserted else {
                continue
            }

            let flags = UInt32(interface.ifa_flags)
            let isLoopback = flags & UInt32(IFF_LOOPBACK) != 0
            let isValid = flags & UInt32(IFF_UP) != 0 && !isLoopback

            guard let data = interface.ifa_data else {
                continue
            }

            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            interfaces.append(
                NetworkInterfaceCounter(
                    name: name,
                    downloadBytes: UInt64(counters.ifi_ibytes),
                    uploadBytes: UInt64(counters.ifi_obytes),
                    isLoopback: isLoopback,
                    isValid: isValid
                )
            )
        }

        return .available(
            NetworkSystemSample(
                counter: NetworkCounterSample(
                    timestamp: timestamp,
                    interfaces: interfaces
                ),
                connectivity: connectivitySource.connectivity
            )
        )
    }
}

final class NWPathConnectivitySource: NetworkConnectivitySource, @unchecked Sendable {
    private let lock = NSLock()
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var started = false
    private var cancelled = false
    private var currentValue: NetworkConnectivity = .unknown

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(
            label: "com.sanepeek.network-path",
            qos: .utility
        )
    ) {
        self.monitor = monitor
        self.queue = queue
        monitor.pathUpdateHandler = { [weak self] path in
            let connectivity: NetworkConnectivity
            switch path.status {
            case .satisfied:
                connectivity = .connected
            case .unsatisfied, .requiresConnection:
                connectivity = .disconnected
            @unknown default:
                connectivity = .unknown
            }

            self?.update(connectivity)
        }
        start()
    }

    var connectivity: NetworkConnectivity {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }

    func start() {
        lock.lock()
        guard !started, !cancelled else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()
        monitor.start(queue: queue)
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        lock.unlock()
        monitor.cancel()
    }

    deinit {
        cancel()
    }

    private func update(_ connectivity: NetworkConnectivity) {
        lock.lock()
        currentValue = connectivity
        lock.unlock()
    }
}

nonisolated enum BatteryPowerSourceState: Sendable, Equatable {
    case ac
    case battery
    case offline
    case unknown
}

nonisolated struct BatterySystemSample: Sendable, Equatable {
    let isPresent: Bool
    let currentCapacity: Int64?
    let maximumCapacity: Int64?
    let isCharging: Bool?
    let powerSourceState: BatteryPowerSourceState
    let timeToEmptyMinutes: Int64?
    let timeToFullChargeMinutes: Int64?
    let designCapacity: Int64?

    init(
        isPresent: Bool,
        currentCapacity: Int64?,
        maximumCapacity: Int64?,
        isCharging: Bool?,
        powerSourceState: BatteryPowerSourceState = .unknown,
        timeToEmptyMinutes: Int64?,
        timeToFullChargeMinutes: Int64?,
        designCapacity: Int64?
    ) {
        self.isPresent = isPresent
        self.currentCapacity = currentCapacity
        self.maximumCapacity = maximumCapacity
        self.isCharging = isCharging
        self.powerSourceState = powerSourceState
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.designCapacity = designCapacity
    }
}

nonisolated protocol BatterySystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<BatterySystemSample>
}

nonisolated struct LiveBatteryReader: BatteryReader {
    private let adapter: any BatterySystemAdapter

    init(adapter: any BatterySystemAdapter = IOKitBatterySystemAdapter()) {
        self.adapter = adapter
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<BatterySnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            guard sample.isPresent else {
                return .unavailable(.notPresent)
            }

            let percentage: Double?
            if let currentCapacity = sample.currentCapacity,
               let maximumCapacity = sample.maximumCapacity
            {
                guard currentCapacity >= 0,
                      maximumCapacity > 0,
                      currentCapacity <= maximumCapacity
                else {
                    return .failed(MetricFailure(kind: .invalidData))
                }
                percentage = Double(currentCapacity) / Double(maximumCapacity)
            } else {
                percentage = nil
            }

            let healthPercentage: Double?
            if let designCapacity = sample.designCapacity {
                guard designCapacity > 0 else {
                    return .failed(MetricFailure(kind: .invalidData))
                }

                if let maximumCapacity = sample.maximumCapacity {
                    guard maximumCapacity >= 0 else {
                        return .failed(MetricFailure(kind: .invalidData))
                    }
                    healthPercentage = min(
                        max(Double(maximumCapacity) / Double(designCapacity), 0),
                        1
                    )
                } else {
                    healthPercentage = nil
                }
            } else {
                healthPercentage = nil
            }

            let chargingState = chargingState(for: sample)
            let timeRemaining = timeRemaining(for: sample)

            return .available(
                BatterySnapshot(
                    timestamp: timestamp,
                    percentage: percentage,
                    chargingState: chargingState,
                    timeRemaining: timeRemaining,
                    healthPercentage: healthPercentage
                )
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            return .failed(failure)
        }
    }

    private func chargingState(for sample: BatterySystemSample) -> BatteryChargingState {
        if sample.isCharging == true {
            return .charging
        }

        if let currentCapacity = sample.currentCapacity,
           let maximumCapacity = sample.maximumCapacity,
           maximumCapacity > 0,
           currentCapacity >= maximumCapacity
        {
            return .charged
        }

        switch sample.powerSourceState {
        case .battery:
            return .unplugged
        case .ac:
            return .charged
        case .offline, .unknown:
            return .unknown
        }
    }

    private func timeRemaining(for sample: BatterySystemSample) -> TimeInterval? {
        let minutes = sample.isCharging == true
            ? sample.timeToFullChargeMinutes
            : sample.timeToEmptyMinutes

        guard let minutes, minutes >= 0 else {
            return nil
        }

        return TimeInterval(minutes) * 60
    }
}

nonisolated struct IOKitBatterySystemAdapter: BatterySystemAdapter {
    private enum Key {
        static let currentCapacity = "Current Capacity"
        static let designCapacity = "DesignCapacity"
        static let isCharging = "Is Charging"
        static let isPresent = "Is Present"
        static let maxCapacity = "Max Capacity"
        static let powerSourceState = "Power Source State"
        static let timeToEmpty = "Time to Empty"
        static let timeToFullCharge = "Time to Full Charge"
        static let transportType = "Transport Type"
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<BatterySystemSample> {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unavailable(.notPresent)
        }

        let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo).takeRetainedValue()
        let count = CFArrayGetCount(powerSources)
        guard count > 0 else {
            return .unavailable(.notPresent)
        }

        var nonPresentBattery: BatterySystemSample?

        for index in 0..<count {
            let powerSource = CFArrayGetValueAtIndex(powerSources, index)
            guard let powerSource else {
                continue
            }

            let powerSourceRef = Unmanaged<CFTypeRef>
                .fromOpaque(powerSource)
                .takeUnretainedValue()
            guard
                  let description = IOPSGetPowerSourceDescription(
                    powerSourcesInfo,
                    powerSourceRef
                  )?.takeUnretainedValue()
            else {
                continue
            }

            let dictionary = description as NSDictionary
            guard let transportType = dictionary[Key.transportType] as? String,
                  transportType == "InternalBattery"
            else {
                continue
            }

            let sample = BatterySystemSample(
                isPresent: number(in: dictionary, for: Key.isPresent)?.boolValue ?? false,
                currentCapacity: number(in: dictionary, for: Key.currentCapacity)?.int64Value,
                maximumCapacity: number(in: dictionary, for: Key.maxCapacity)?.int64Value,
                isCharging: number(in: dictionary, for: Key.isCharging)?.boolValue,
                powerSourceState: powerSourceState(
                    from: dictionary[Key.powerSourceState] as? String
                ),
                timeToEmptyMinutes: number(in: dictionary, for: Key.timeToEmpty)?.int64Value,
                timeToFullChargeMinutes: number(in: dictionary, for: Key.timeToFullCharge)?.int64Value,
                designCapacity: number(in: dictionary, for: Key.designCapacity)?.int64Value
            )

            if sample.isPresent {
                return .available(sample)
            }
            nonPresentBattery = sample
        }

        if let nonPresentBattery {
            return .available(nonPresentBattery)
        }
        return .unavailable(.notPresent)
    }

    private func number(in dictionary: NSDictionary, for key: String) -> NSNumber? {
        dictionary[key] as? NSNumber
    }

    private func powerSourceState(from value: String?) -> BatteryPowerSourceState {
        switch value {
        case "AC Power":
            .ac
        case "Battery Power":
            .battery
        case "Off Line":
            .offline
        default:
            .unknown
        }
    }
}

nonisolated struct GPUCapability: Sendable, Equatable {
    let isSupported: Bool
    let name: String?

    init(isSupported: Bool, name: String? = nil) {
        self.isSupported = isSupported
        self.name = name
    }
}

nonisolated struct GPUSystemSample: Sendable, Equatable {
    let utilization: Double?
    let name: String?

    init(utilization: Double?, name: String? = nil) {
        self.utilization = utilization
        self.name = name
    }
}

nonisolated protocol GPUSystemAdapter: Sendable {
    var capability: GPUCapability { get }

    func read(at timestamp: MetricTimestamp) -> MetricResult<GPUSystemSample>
}

nonisolated struct LiveGPUReader: GPUReader {
    private let adapter: any GPUSystemAdapter

    init(adapter: any GPUSystemAdapter = IORegistryGPUAdapter()) {
        self.adapter = adapter
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<GPUSnapshot> {
        guard adapter.capability.isSupported else {
            return .unavailable(.unsupported)
        }

        switch adapter.read(at: timestamp) {
        case let .available(sample):
            if let utilization = sample.utilization {
                guard utilization.isFinite, (0...1).contains(utilization) else {
                    return .failed(MetricFailure(kind: .invalidData))
                }
            }

            return .available(
                GPUSnapshot(
                    timestamp: timestamp,
                    utilization: sample.utilization,
                    name: sample.name ?? adapter.capability.name
                )
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            return .failed(failure)
        }
    }
}

nonisolated struct IORegistryGPUAdapter: GPUSystemAdapter {
    let capability: GPUCapability

    init() {
        capability = Self.discoverCapability()
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<GPUSystemSample> {
        .unavailable(.unsupported)
    }

    private static func discoverCapability() -> GPUCapability {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator"),
              IOServiceGetMatchingServices(
                kIOMainPortDefault,
                matching,
                &iterator
              ) == KERN_SUCCESS
        else {
            return GPUCapability(isSupported: false)
        }
        defer {
            IOObjectRelease(iterator)
        }

        var discoveredName: String?
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else {
                break
            }
            defer {
                IOObjectRelease(service)
            }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            let result = nameBuffer.withUnsafeMutableBufferPointer { buffer in
                IORegistryEntryGetName(service, buffer.baseAddress!)
            }
            if result == KERN_SUCCESS {
                let nameBytes = nameBuffer
                    .prefix(while: { $0 != 0 })
                    .map { UInt8(bitPattern: $0) }
                let name = String(decoding: nameBytes, as: UTF8.self)
                if !name.isEmpty {
                    discoveredName = name
                    break
                }
            }
        }

        return GPUCapability(isSupported: false, name: discoveredName)
    }
}

import Foundation
import os

nonisolated enum MetricHistoryKind: CaseIterable, Hashable, Sendable {
    case cpuUtilization
    case cpuUserUtilization
    case cpuSystemUtilization
    case memoryUsedBytes
    case memoryAppUtilization
    case memoryWiredUtilization
    case memoryCompressedUtilization
    case networkDownloadBytesPerSecond
    case networkUploadBytesPerSecond
    case gpuUtilization
    case temperatureHottestCelsius
}

actor MetricsEngine {
    private let cpuReader: any CPUReader
    private let memoryReader: any MemoryReader
    private let storageReader: any StorageReader
    private let networkReader: any NetworkReader
    private let batteryReader: any BatteryReader
    private let gpuReader: any GPUReader
    private let temperatureReader: any TemperatureReader
    private let clock: any MetricClock
    private let fastScheduler: any MetricScheduler
    private let slowScheduler: any MetricScheduler
    private let logger: Logger
    private let signposter: OSSignposter

    private var cadencePolicy: CadencePolicy
    private var history: [MetricHistoryKind: MetricRingBuffer<Double>]
    /// Metrics currently read by the polling loops. Defaults to all seven so behavior is
    /// unchanged until a caller opts into selective polling via `setActiveMetrics(_:)`.
    private var activeMetrics: Set<MetricKind> = Set(MetricKind.allCases)

    private var fastTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var isPaused = false
    private var isStopped = false

    private var lastGoodCPU: CPUSnapshot?
    private var lastGoodMemory: MemorySnapshot?
    private var lastGoodStorage: StorageSnapshot?
    private var lastGoodNetwork: NetworkSnapshot?
    private var lastGoodBattery: BatterySnapshot?
    private var lastGoodGPU: GPUSnapshot?
    private var lastGoodTemperature: TemperatureSnapshot?

    private var publishedCPU: CPUSnapshot?
    private var publishedMemory: MemorySnapshot?
    private var publishedStorage: StorageSnapshot?
    private var publishedNetwork: NetworkSnapshot?
    private var publishedBattery: BatterySnapshot?
    private var publishedGPU: GPUSnapshot?
    private var publishedTemperature: TemperatureSnapshot?

    private var lastPublishedMonotonicSeconds: TimeInterval = -Double.infinity
    private var hasPublishedFirstSnapshot = false
    private var launchSignpostState: OSSignpostIntervalState?

    private var stream: AsyncStream<MetricsSnapshot>?
    private var continuation: AsyncStream<MetricsSnapshot>.Continuation?

    init(
        cpuReader: any CPUReader = LiveCPUReader(),
        memoryReader: any MemoryReader = LiveMemoryReader(),
        storageReader: any StorageReader = LiveStorageReader(),
        networkReader: any NetworkReader = LiveNetworkReader(),
        batteryReader: any BatteryReader = LiveBatteryReader(),
        gpuReader: any GPUReader = LiveGPUReader(),
        temperatureReader: any TemperatureReader = LiveTemperatureReader(),
        clock: any MetricClock = SystemMetricClock(),
        fastScheduler: any MetricScheduler = SystemMetricScheduler(),
        slowScheduler: any MetricScheduler = SystemMetricScheduler(),
        cadencePolicy: CadencePolicy = CadencePolicy(),
        historyRetention: TimeInterval = 60,
        historyCapacity: Int = 60,
        logger: Logger = Logger(subsystem: "com.sanepeek.app", category: "MetricsEngine"),
        signposter: OSSignposter = OSSignposter(subsystem: "com.sanepeek.app", category: "MetricsEngine")
    ) {
        self.cpuReader = cpuReader
        self.memoryReader = memoryReader
        self.storageReader = storageReader
        self.networkReader = networkReader
        self.batteryReader = batteryReader
        self.gpuReader = gpuReader
        self.temperatureReader = temperatureReader
        self.clock = clock
        self.fastScheduler = fastScheduler
        self.slowScheduler = slowScheduler
        self.cadencePolicy = cadencePolicy
        self.logger = logger
        self.signposter = signposter
        self.history = Dictionary(
            uniqueKeysWithValues: MetricHistoryKind.allCases.map {
                ($0, MetricRingBuffer<Double>(retention: historyRetention, capacity: historyCapacity))
            }
        )
    }

    deinit {
        fastTask?.cancel()
        slowTask?.cancel()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStopped, fastTask == nil, slowTask == nil else { return }
        isPaused = false
        logger.info("MetricsEngine starting polling loops")
        if !hasPublishedFirstSnapshot, launchSignpostState == nil {
            launchSignpostState = signposter.beginInterval("Launch")
        }
        fastTask = Task { [weak self] in await self?.runFastLoop() }
        slowTask = Task { [weak self] in await self?.runSlowLoop() }
    }

    func pause() {
        guard !isStopped, !isPaused else { return }
        logger.info("MetricsEngine pausing polling loops")
        isPaused = true
        cancelTasks()
    }

    func resume() {
        guard !isStopped, isPaused else { return }
        logger.info("MetricsEngine resuming polling loops")
        start()
    }

    func stop() {
        guard !isStopped else { return }
        logger.info("MetricsEngine stopping")
        isStopped = true
        isPaused = false
        cancelTasks()
        continuation?.finish()
    }

    func updateCadence(_ policy: CadencePolicy) {
        guard cadencePolicy != policy else { return }
        logger.info("MetricsEngine updating cadence")
        cadencePolicy = policy
        guard !isStopped, !isPaused, fastTask != nil else { return }
        fastTask?.cancel()
        fastTask = Task { [weak self] in await self?.runFastLoop() }
    }

    /// Restricts the polling loops to reading only these metrics; the rest keep publishing
    /// their last-known-good value unchanged instead of being read. Callers that want polling
    /// stopped entirely should use `pause()` instead of passing an empty set.
    func setActiveMetrics(_ metrics: Set<MetricKind>) {
        activeMetrics = metrics
    }

    private func cancelTasks() {
        fastTask?.cancel()
        slowTask?.cancel()
        fastTask = nil
        slowTask = nil
    }

    // MARK: - Publication

    func snapshots() -> AsyncStream<MetricsSnapshot> {
        if let stream {
            return stream
        }
        let (newStream, newContinuation) = AsyncStream.makeStream(
            of: MetricsSnapshot.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        stream = newStream
        continuation = newContinuation
        return newStream
    }

    func currentSnapshot() -> MetricsSnapshot {
        combinedSnapshot(at: clock.now())
    }

    func history(for kind: MetricHistoryKind) -> [MetricSample<Double>] {
        history[kind]?.samples ?? []
    }

    // MARK: - Polling loops

    private func runFastLoop() async {
        while !Task.isCancelled {
            let tick = clock.now()
            let cycleState = signposter.beginInterval("PollingCycle.fast")

            async let cpuResult = readIfActive(.cpu) { await self.readCPU(at: tick) }
            async let memoryResult = readIfActive(.memory) { await self.readMemory(at: tick) }
            async let networkResult = readIfActive(.network) { await self.readNetwork(at: tick) }
            async let gpuResult = readIfActive(.gpu) { await self.readGPU(at: tick) }

            updateFastMetrics(
                cpu: await cpuResult,
                memory: await memoryResult,
                network: await networkResult,
                gpu: await gpuResult,
                at: tick
            )
            publish(at: tick)
            signposter.endInterval("PollingCycle.fast", cycleState)

            do {
                try await fastScheduler.wait(for: cadencePolicy.interval(for: .cpu))
            } catch {
                return
            }
        }
    }

    private func runSlowLoop() async {
        while !Task.isCancelled {
            let tick = clock.now()
            let cycleState = signposter.beginInterval("PollingCycle.slow")

            async let storageResult = readIfActive(.storage) { await self.readStorage(at: tick) }
            async let batteryResult = readIfActive(.battery) { await self.readBattery(at: tick) }
            async let temperatureResult = readIfActive(.temperature) { await self.readTemperature(at: tick) }

            updateSlowMetrics(
                storage: await storageResult,
                battery: await batteryResult,
                temperature: await temperatureResult,
                at: tick
            )
            publish(at: tick)
            signposter.endInterval("PollingCycle.slow", cycleState)

            do {
                try await slowScheduler.wait(for: cadencePolicy.interval(for: .storage))
            } catch {
                return
            }
        }
    }

    // MARK: - Selective polling

    /// Skips `read` for a metric outside `activeMetrics`, returning `nil` so the caller leaves
    /// that metric's last-known-good published value untouched instead of overwriting it.
    private func readIfActive<T>(_ metric: MetricKind, _ read: () async -> MetricResult<T>) async -> MetricResult<T>? {
        guard activeMetrics.contains(metric) else { return nil }
        return await read()
    }

    // MARK: - Reader cost signposts

    private func readCPU(at tick: MetricTimestamp) async -> MetricResult<CPUSnapshot> {
        let state = signposter.beginInterval("ReaderCost.cpu")
        defer { signposter.endInterval("ReaderCost.cpu", state) }
        return await cpuReader.read(at: tick)
    }

    private func readMemory(at tick: MetricTimestamp) async -> MetricResult<MemorySnapshot> {
        let state = signposter.beginInterval("ReaderCost.memory")
        defer { signposter.endInterval("ReaderCost.memory", state) }
        return await memoryReader.read(at: tick)
    }

    private func readStorage(at tick: MetricTimestamp) async -> MetricResult<StorageSnapshot> {
        let state = signposter.beginInterval("ReaderCost.storage")
        defer { signposter.endInterval("ReaderCost.storage", state) }
        return await storageReader.read(at: tick)
    }

    private func readNetwork(at tick: MetricTimestamp) async -> MetricResult<NetworkSnapshot> {
        let state = signposter.beginInterval("ReaderCost.network")
        defer { signposter.endInterval("ReaderCost.network", state) }
        return await networkReader.read(at: tick)
    }

    private func readBattery(at tick: MetricTimestamp) async -> MetricResult<BatterySnapshot> {
        let state = signposter.beginInterval("ReaderCost.battery")
        defer { signposter.endInterval("ReaderCost.battery", state) }
        return await batteryReader.read(at: tick)
    }

    private func readGPU(at tick: MetricTimestamp) async -> MetricResult<GPUSnapshot> {
        let state = signposter.beginInterval("ReaderCost.gpu")
        defer { signposter.endInterval("ReaderCost.gpu", state) }
        return await gpuReader.read(at: tick)
    }

    private func readTemperature(at tick: MetricTimestamp) async -> MetricResult<TemperatureSnapshot> {
        let state = signposter.beginInterval("ReaderCost.temperature")
        defer { signposter.endInterval("ReaderCost.temperature", state) }
        return await temperatureReader.read(at: tick)
    }

    // MARK: - Merge and history

    private func updateFastMetrics(
        cpu cpuResult: MetricResult<CPUSnapshot>?,
        memory memoryResult: MetricResult<MemorySnapshot>?,
        network networkResult: MetricResult<NetworkSnapshot>?,
        gpu gpuResult: MetricResult<GPUSnapshot>?,
        at tick: MetricTimestamp
    ) {
        if let cpuResult {
            publishedCPU = mergedCPU(cpuResult, at: tick)
            if case .available = cpuResult, let utilization = publishedCPU?.utilization {
                history[.cpuUtilization]?.append(MetricSample(timestamp: tick, value: utilization))
            }
            if case .available = cpuResult, let userUtilization = publishedCPU?.userUtilization {
                history[.cpuUserUtilization]?.append(MetricSample(timestamp: tick, value: userUtilization))
            }
            if case .available = cpuResult, let systemUtilization = publishedCPU?.systemUtilization {
                history[.cpuSystemUtilization]?.append(MetricSample(timestamp: tick, value: systemUtilization))
            }
        }
        if let memoryResult {
            publishedMemory = mergedMemory(memoryResult, at: tick)
            if case .available = memoryResult, let usedBytes = publishedMemory?.usedBytes {
                history[.memoryUsedBytes]?.append(MetricSample(timestamp: tick, value: Double(usedBytes)))
            }
            if case .available = memoryResult, let appUtilization = publishedMemory?.appUtilization {
                history[.memoryAppUtilization]?.append(MetricSample(timestamp: tick, value: appUtilization))
            }
            if case .available = memoryResult, let wiredUtilization = publishedMemory?.wiredUtilization {
                history[.memoryWiredUtilization]?.append(MetricSample(timestamp: tick, value: wiredUtilization))
            }
            if case .available = memoryResult, let compressedUtilization = publishedMemory?.compressedUtilization {
                history[.memoryCompressedUtilization]?.append(MetricSample(timestamp: tick, value: compressedUtilization))
            }
        }
        if let networkResult {
            publishedNetwork = mergedNetwork(networkResult, at: tick)
            if case .available = networkResult {
                if let download = publishedNetwork?.downloadBytesPerSecond {
                    history[.networkDownloadBytesPerSecond]?.append(MetricSample(timestamp: tick, value: download))
                }
                if let upload = publishedNetwork?.uploadBytesPerSecond {
                    history[.networkUploadBytesPerSecond]?.append(MetricSample(timestamp: tick, value: upload))
                }
            }
        }
        if let gpuResult {
            publishedGPU = mergedGPU(gpuResult, at: tick)
            if case .available = gpuResult, let utilization = publishedGPU?.utilization {
                history[.gpuUtilization]?.append(MetricSample(timestamp: tick, value: utilization))
            }
        }
    }

    private func updateSlowMetrics(
        storage storageResult: MetricResult<StorageSnapshot>?,
        battery batteryResult: MetricResult<BatterySnapshot>?,
        temperature temperatureResult: MetricResult<TemperatureSnapshot>?,
        at tick: MetricTimestamp
    ) {
        if let storageResult {
            publishedStorage = mergedStorage(storageResult, at: tick)
        }
        if let batteryResult {
            publishedBattery = mergedBattery(batteryResult, at: tick)
        }
        if let temperatureResult {
            publishedTemperature = mergedTemperature(temperatureResult, at: tick)
            if case .available = temperatureResult {
                let hottest = [publishedTemperature?.cpuCelsius, publishedTemperature?.gpuCelsius].compactMap { $0 }.max()
                if let hottest {
                    history[.temperatureHottestCelsius]?.append(MetricSample(timestamp: tick, value: hottest))
                }
            }
        }
    }

    private func mergedCPU(_ result: MetricResult<CPUSnapshot>, at tick: MetricTimestamp) -> CPUSnapshot {
        if case let .available(snapshot) = result {
            lastGoodCPU = snapshot
            return snapshot
        }
        let previous = lastGoodCPU
        return CPUSnapshot(
            timestamp: tick,
            availability: result.availability,
            utilization: previous?.utilization,
            userUtilization: previous?.userUtilization,
            systemUtilization: previous?.systemUtilization,
            logicalCoreCount: previous?.logicalCoreCount,
            performanceCoreCount: previous?.performanceCoreCount,
            efficiencyCoreCount: previous?.efficiencyCoreCount,
            chipName: previous?.chipName
        )
    }

    private func mergedMemory(_ result: MetricResult<MemorySnapshot>, at tick: MetricTimestamp) -> MemorySnapshot {
        if case let .available(snapshot) = result {
            lastGoodMemory = snapshot
            return snapshot
        }
        let previous = lastGoodMemory
        return MemorySnapshot(
            timestamp: tick,
            availability: result.availability,
            usedBytes: previous?.usedBytes,
            availableBytes: previous?.availableBytes,
            pressure: previous?.pressure,
            appUtilization: previous?.appUtilization,
            wiredUtilization: previous?.wiredUtilization,
            compressedUtilization: previous?.compressedUtilization
        )
    }

    private func mergedStorage(_ result: MetricResult<StorageSnapshot>, at tick: MetricTimestamp) -> StorageSnapshot {
        if case let .available(snapshot) = result {
            lastGoodStorage = snapshot
            return snapshot
        }
        let previous = lastGoodStorage
        return StorageSnapshot(
            timestamp: tick,
            availability: result.availability,
            usedBytes: previous?.usedBytes,
            availableBytes: previous?.availableBytes,
            totalBytes: previous?.totalBytes
        )
    }

    private func mergedNetwork(_ result: MetricResult<NetworkSnapshot>, at tick: MetricTimestamp) -> NetworkSnapshot {
        if case let .available(snapshot) = result {
            lastGoodNetwork = snapshot
            return snapshot
        }
        let previous = lastGoodNetwork
        return NetworkSnapshot(
            timestamp: tick,
            availability: result.availability,
            downloadBytesPerSecond: previous?.downloadBytesPerSecond,
            uploadBytesPerSecond: previous?.uploadBytesPerSecond,
            connectivity: previous?.connectivity,
            interfaceNames: previous?.interfaceNames,
            primaryInterfaceName: previous?.primaryInterfaceName
        )
    }

    private func mergedBattery(_ result: MetricResult<BatterySnapshot>, at tick: MetricTimestamp) -> BatterySnapshot {
        if case let .available(snapshot) = result {
            lastGoodBattery = snapshot
            return snapshot
        }
        let previous = lastGoodBattery
        return BatterySnapshot(
            timestamp: tick,
            availability: result.availability,
            percentage: previous?.percentage,
            chargingState: previous?.chargingState,
            timeRemaining: previous?.timeRemaining,
            healthPercentage: previous?.healthPercentage
        )
    }

    private func mergedGPU(_ result: MetricResult<GPUSnapshot>, at tick: MetricTimestamp) -> GPUSnapshot {
        if case let .available(snapshot) = result {
            lastGoodGPU = snapshot
            return snapshot
        }
        let previous = lastGoodGPU
        return GPUSnapshot(
            timestamp: tick,
            availability: result.availability,
            utilization: previous?.utilization,
            name: previous?.name
        )
    }

    private func mergedTemperature(_ result: MetricResult<TemperatureSnapshot>, at tick: MetricTimestamp) -> TemperatureSnapshot {
        if case let .available(snapshot) = result {
            lastGoodTemperature = snapshot
            return snapshot
        }
        let previous = lastGoodTemperature
        return TemperatureSnapshot(
            timestamp: tick,
            availability: result.availability,
            cpuCelsius: previous?.cpuCelsius,
            gpuCelsius: previous?.gpuCelsius
        )
    }

    private func combinedSnapshot(at timestamp: MetricTimestamp) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            cpu: publishedCPU,
            memory: publishedMemory,
            storage: publishedStorage,
            network: publishedNetwork,
            battery: publishedBattery,
            gpu: publishedGPU,
            temperature: publishedTemperature
        )
    }

    private func publish(at tick: MetricTimestamp) {
        guard tick.monotonicSeconds >= lastPublishedMonotonicSeconds else {
            logger.debug("Dropping out-of-order snapshot tick")
            return
        }
        lastPublishedMonotonicSeconds = tick.monotonicSeconds
        continuation?.yield(combinedSnapshot(at: tick))

        if !hasPublishedFirstSnapshot {
            hasPublishedFirstSnapshot = true
            if let launchSignpostState {
                signposter.endInterval("Launch", launchSignpostState)
                self.launchSignpostState = nil
            }
            logger.info("MetricsEngine published first snapshot")
        }
    }
}

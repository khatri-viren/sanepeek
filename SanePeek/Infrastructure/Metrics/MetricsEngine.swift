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
    /// Incremented whenever the slow loop is replaced or canceled. A reader is allowed to
    /// ignore task cancellation, so the generation is the publication boundary that prevents
    /// an older loop from overwriting values produced by its replacement.
    private var slowLoopGeneration = 0
    private var isPaused = false
    private var isStopped = false

    /// The last desired activity accepted from the lifecycle coordinator. Keeping the value in
    /// the actor makes repeated equivalent inputs idempotent and lets the actor reject stale
    /// unstructured tasks without exposing its reader-loop implementation to `AppState`.
    private var lastActivityState: MonitoringActivityState?
    private var lastActivityGeneration: UInt64 = 0

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

    /// When temperature was last sampled, so it can keep its own cadence while riding the fast
    /// loop's wakeup. `-infinity` makes the first tick always due.
    private var lastTemperatureMonotonicSeconds: TimeInterval = -Double.infinity

    private var lastPublishedMonotonicSeconds: TimeInterval = -Double.infinity
    private var hasPublishedFirstSnapshot = false
    private var launchSignpostState: OSSignpostIntervalState?

    private var stream: AsyncStream<MetricsSnapshot>?
    private var continuation: AsyncStream<MetricsSnapshot>.Continuation?
    private var observationStream: AsyncStream<MetricsObservation>?
    private var observationContinuation: AsyncStream<MetricsObservation>.Continuation?

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
        historyRetention: TimeInterval = MetricHistoryDefaults.retention,
        historyCapacity: Int = MetricHistoryDefaults.sampleCapacity,
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
        // Install the continuation before either polling task can publish. Without this,
        // the first samples can be emitted into a nil continuation and the UI waits for the
        // next cadence interval to see them.
        _ = snapshots()
        _ = observations()
        if !hasPublishedFirstSnapshot, launchSignpostState == nil {
            launchSignpostState = signposter.beginInterval("Launch")
        }
        fastTask = Task { [weak self] in await self?.runFastLoop() }
        slowLoopGeneration += 1
        let generation = slowLoopGeneration
        slowTask = Task { [weak self] in await self?.runSlowLoop(generation: generation) }
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
        observationContinuation?.finish()
    }

    func updateCadence(_ policy: CadencePolicy) {
        guard cadencePolicy != policy else { return }
        // Debug, not info: this fires on every popup/dashboard open and close (full-coverage
        // cadence swaps in and out), not on a noteworthy lifecycle transition like start/stop.
        logger.debug("MetricsEngine updating cadence")
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

    /// Applies one complete desired activity state. The generation check is intentionally inside
    /// the actor: separate tasks created by lifecycle callbacks may arrive out of order, and a
    /// stale task must not resume polling after a newer pause or replace a newer metric set.
    func reconcileMonitoringActivity(_ activity: MonitoringActivityState, generation: UInt64) {
        guard !isStopped, generation > lastActivityGeneration else { return }
        lastActivityGeneration = generation

        let previousActivity = lastActivityState
        let activityAlreadyApplied = previousActivity == activity && isRunStateConsistent(with: activity)
        guard !activityAlreadyApplied else { return }
        lastActivityState = activity

        switch activity {
        case .paused:
            pause()

        case .background, .foreground:
            setActiveMetrics(activity.activeMetrics)
            if let cadence = activity.cadence {
                updateCadence(cadence)
            }

            // Starting or resuming already samples immediately. Only interrupt an existing
            // background slow wait when a visible view is newly entering the foreground.
            let startedPolling: Bool
            if isPaused {
                resume()
                startedPolling = true
            } else if fastTask == nil && slowTask == nil {
                start()
                startedPolling = true
            } else {
                startedPolling = false
            }

            if activity.isForeground,
               previousActivity?.isForeground == false,
               !startedPolling
            {
                refreshSlowMetrics()
            }
        }
    }

    private func isRunStateConsistent(with activity: MonitoringActivityState) -> Bool {
        switch activity {
        case .paused:
            isPaused && fastTask == nil && slowTask == nil
        case .background, .foreground:
            !isPaused && (fastTask != nil || slowTask != nil)
        }
    }

    /// Interrupts the slow loop's long background wait so a newly visible view receives
    /// Storage and Battery values immediately. The loop always samples before its first wait,
    /// so restarting it is also sufficient when the engine was paused and then resumed.
    func refreshSlowMetrics() {
        guard !isStopped, !isPaused, slowTask != nil else { return }
        slowTask?.cancel()
        slowLoopGeneration += 1
        let generation = slowLoopGeneration
        slowTask = Task { [weak self] in await self?.runSlowLoop(generation: generation) }
    }

    private func cancelTasks() {
        fastTask?.cancel()
        slowTask?.cancel()
        slowLoopGeneration += 1
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

    /// Returns the coherent publication stream used by dashboard adapters. Each yielded value
    /// contains the snapshot and every bounded history series from the same actor turn.
    func observations() -> AsyncStream<MetricsObservation> {
        if let observationStream {
            return observationStream
        }
        let (newStream, newContinuation) = AsyncStream.makeStream(
            of: MetricsObservation.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        observationStream = newStream
        observationContinuation = newContinuation
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

            // Decided synchronously, before the concurrent reads, so the due-check and its
            // bookkeeping cannot interleave with another tick.
            let temperatureIsDue = claimTemperatureSlot(at: tick)

            async let cpuResult = readIfActive(.cpu) { await self.readCPU(at: tick) }
            async let memoryResult = readIfActive(.memory) { await self.readMemory(at: tick) }
            async let networkResult = readIfActive(.network) { await self.readNetwork(at: tick) }
            async let gpuResult = readIfActive(.gpu) { await self.readGPU(at: tick) }
            async let temperatureResult = readTemperatureIfDue(temperatureIsDue, at: tick)

            updateFastMetrics(
                cpu: await cpuResult,
                memory: await memoryResult,
                network: await networkResult,
                gpu: await gpuResult,
                temperature: await temperatureResult,
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

    private func runSlowLoop(generation: Int) async {
        while !Task.isCancelled {
            let tick = clock.now()
            let cycleState = signposter.beginInterval("PollingCycle.slow")

            async let storageResult = readIfActive(.storage) { await self.readStorage(at: tick) }
            async let batteryResult = readIfActive(.battery) { await self.readBattery(at: tick) }

            let storage = await storageResult
            let battery = await batteryResult
            guard generation == slowLoopGeneration, !Task.isCancelled else { return }
            updateSlowMetrics(
                storage: storage,
                battery: battery,
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

    /// Temperature rides the fast loop's existing wakeup instead of owning a timer, but samples
    /// on its own slower cadence. Reading it every fast tick would cost ~0.21% CPU at 1 Hz —
    /// about the app's whole idle budget again — because each sample is nine synchronous SMC
    /// round trips. Reusing the fast wakeup keeps the idle wakeup count unchanged.
    ///
    /// Returns whether this tick owns the next sample, marking the slot as taken if so.
    private func claimTemperatureSlot(at tick: MetricTimestamp) -> Bool {
        guard activeMetrics.contains(.temperature) else { return false }
        let interval = cadencePolicy.interval(for: .temperature)
        guard tick.monotonicSeconds - lastTemperatureMonotonicSeconds >= interval else {
            return false
        }
        lastTemperatureMonotonicSeconds = tick.monotonicSeconds
        return true
    }

    private func readTemperatureIfDue(
        _ isDue: Bool,
        at tick: MetricTimestamp
    ) async -> MetricResult<TemperatureSnapshot>? {
        guard isDue else { return nil }
        return await readTemperature(at: tick)
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
        temperature temperatureResult: MetricResult<TemperatureSnapshot>?,
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

    private func updateSlowMetrics(
        storage storageResult: MetricResult<StorageSnapshot>?,
        battery batteryResult: MetricResult<BatterySnapshot>?,
        at tick: MetricTimestamp
    ) {
        if let storageResult {
            publishedStorage = mergedStorage(storageResult, at: tick)
        }
        if let batteryResult {
            publishedBattery = mergedBattery(batteryResult, at: tick)
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

    private func combinedObservation(at timestamp: MetricTimestamp) -> MetricsObservation {
        MetricsObservation(
            snapshot: combinedSnapshot(at: timestamp),
            histories: Dictionary(
                uniqueKeysWithValues: MetricHistoryKind.allCases.map { kind in
                    (kind, history[kind]?.samples ?? [])
                }
            )
        )
    }

    private func publish(at tick: MetricTimestamp) {
        guard tick.monotonicSeconds >= lastPublishedMonotonicSeconds else {
            logger.debug("Dropping out-of-order snapshot tick")
            return
        }
        lastPublishedMonotonicSeconds = tick.monotonicSeconds
        let observation = combinedObservation(at: tick)
        continuation?.yield(observation.snapshot)
        observationContinuation?.yield(observation)

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

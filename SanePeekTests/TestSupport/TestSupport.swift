import AppKit
import Foundation
import Observation
import Testing

@testable import SanePeek

// MARK: - Swift Testing tags

extension Tag {
    @Tag static var hardwareRequired: Self
}

// MARK: - Isolated process state

@MainActor
final class TestDefaultsSuite {
    let name: String
    let defaults: UserDefaults

    init(prefix: String = "com.sanepeek.tests") {
        name = "\(prefix).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("Unable to create isolated defaults suite \(name)")
        }
        self.defaults = defaults
    }

    func removePersistentDomain() {
        defaults.removePersistentDomain(forName: name)
    }
}

// MARK: - Deterministic fixtures

enum TestFixtureScenario: String, CaseIterable, Sendable {
    case baseline
    case warning
    case critical
    case unavailable
    case gpuUnsupported
    case mixedFailure
    case temperatureUnsupported

    var snapshot: MetricsSnapshot {
        switch self {
        case .baseline:
            MetricFixtures.baseline()
        case .warning:
            MetricFixtures.warning()
        case .critical:
            MetricFixtures.critical()
        case .unavailable:
            MetricFixtures.unavailable()
        case .gpuUnsupported:
            MetricFixtures.gpuUnsupported()
        case .mixedFailure:
            MetricFixtures.mixedFailure()
        case .temperatureUnsupported:
            MetricFixtures.temperatureUnsupported()
        }
    }

    var launchArguments: [String] {
        ["-uiTestFixture", rawValue]
    }
}

// MARK: - Reader and scheduler doubles

actor TestMetricReadRecorder<Snapshot: MetricSnapshot> {
    private var results: [MetricResult<Snapshot>]
    private(set) var timestamps: [MetricTimestamp] = []

    init(results: [MetricResult<Snapshot>] = []) {
        self.results = results
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<Snapshot> {
        timestamps.append(timestamp)
        guard !results.isEmpty else {
            return .unavailable(.noData)
        }
        return results.removeFirst()
    }

    func append(_ result: MetricResult<Snapshot>) {
        results.append(result)
    }

    func readCount() -> Int {
        timestamps.count
    }
}

struct TestMetricReader<Snapshot: MetricSnapshot>: MetricReader {
    let recorder: TestMetricReadRecorder<Snapshot>

    init(results: [MetricResult<Snapshot>] = []) {
        recorder = TestMetricReadRecorder(results: results)
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<Snapshot> {
        await recorder.read(at: timestamp)
    }
}

extension TestMetricReader: CPUReader where Snapshot == CPUSnapshot {}
extension TestMetricReader: MemoryReader where Snapshot == MemorySnapshot {}
extension TestMetricReader: StorageReader where Snapshot == StorageSnapshot {}
extension TestMetricReader: NetworkReader where Snapshot == NetworkSnapshot {}
extension TestMetricReader: BatteryReader where Snapshot == BatterySnapshot {}
extension TestMetricReader: GPUReader where Snapshot == GPUSnapshot {}
extension TestMetricReader: TemperatureReader where Snapshot == TemperatureSnapshot {}

actor TestMetricScheduler: MetricScheduler {
    private(set) var intervals: [TimeInterval] = []
    private var nextWaiterID: UInt64 = 0
    private var waiters: [UInt64: CheckedContinuation<Void, Error>] = [:]
    private var waiterOrder: [UInt64] = []

    func wait(for interval: TimeInterval) async throws {
        intervals.append(interval)
        try Task.checkCancellation()

        let waiterID = nextWaiterID
        nextWaiterID += 1

        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters[waiterID] = continuation
                waiterOrder.append(waiterID)
            }
        }, onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        })

        try Task.checkCancellation()
    }

    func releaseNext() {
        guard let waiterID = waiterOrder.first else { return }
        waiterOrder.removeFirst()
        waiters.removeValue(forKey: waiterID)?.resume()
    }

    func finish() {
        let continuations = waiterOrder.compactMap { waiterID in
            waiters.removeValue(forKey: waiterID)
        }
        waiterOrder.removeAll()

        continuations.forEach { $0.resume(throwing: CancellationError()) }
    }

    func requestedIntervals() -> [TimeInterval] {
        intervals
    }

    private func cancelWaiter(_ waiterID: UInt64) {
        guard let continuation = waiters.removeValue(forKey: waiterID) else { return }
        waiterOrder.removeAll { $0 == waiterID }
        continuation.resume(throwing: CancellationError())
    }
}

// MARK: - Feed double

@MainActor
final class TestMetricsTickFeed: MetricsTickFeed {
    private let stream: AsyncStream<MetricsTick>
    private let continuation: AsyncStream<MetricsTick>.Continuation

    init() {
        var continuation: AsyncStream<MetricsTick>.Continuation?
        stream = AsyncStream { continuation = $0 }
        guard let continuation else {
            preconditionFailure("Unable to create metrics tick stream")
        }
        self.continuation = continuation
    }

    func ticks() -> AsyncStream<MetricsTick> {
        stream
    }

    func send(_ tick: MetricsTick) {
        continuation.yield(tick)
    }

    func finish() {
        continuation.finish()
    }
}

// MARK: - Settings service double

@MainActor
final class TestLaunchAtLoginService: LaunchAtLoginService {
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    var status: LaunchAtLoginStatus
    var registerError: Error?
    var unregisterError: Error?

    init(status: LaunchAtLoginStatus = .notRegistered) {
        self.status = status
    }

    func currentStatus() -> LaunchAtLoginStatus {
        status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }
}

struct TestServiceError: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
@Observable
final class TestUpdaterService: UpdaterService {
    var canCheckForUpdates: Bool
    let currentVersion: String
    private(set) var checkForUpdatesCallCount = 0

    init(canCheckForUpdates: Bool = true, currentVersion: String = "test (1)") {
        self.canCheckForUpdates = canCheckForUpdates
        self.currentVersion = currentVersion
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }
}

// MARK: - Async assertions and AppKit cleanup

enum TestAsync {
    static func waitUntil(
        timeout: Duration = .seconds(2),
        pollEvery: Duration = .milliseconds(10),
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !(await condition()) {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: pollEvery)
        }
        return true
    }
}

@MainActor
enum AppKitTestSupport {
    static func withConfiguredPopoverController<T>(
        appState: AppState,
        operation: (MenuBarPopoverController) throws -> T
    ) rethrows -> T {
        let controller = MenuBarPopoverController()
        controller.configure(appState: appState)
        defer { controller.tearDown() }
        return try operation(controller)
    }
}

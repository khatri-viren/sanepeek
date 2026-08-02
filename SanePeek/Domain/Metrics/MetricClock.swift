import Foundation

nonisolated protocol MetricClock: Sendable {
    func now() -> MetricTimestamp
}

nonisolated struct SystemMetricClock: MetricClock, Sendable {
    func now() -> MetricTimestamp {
        MetricTimestamp(
            date: Date(),
            monotonicSeconds: Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        )
    }
}

nonisolated struct TestMetricClock: MetricClock, Sendable {
    private let current: MetricTimestamp

    init(startingAt timestamp: MetricTimestamp = .zero) {
        self.current = timestamp
    }

    func now() -> MetricTimestamp {
        current
    }

    func advanced(by seconds: TimeInterval) -> Self {
        Self(startingAt: current.advanced(by: seconds))
    }
}

nonisolated protocol MetricScheduler: Sendable {
    func wait(for interval: TimeInterval) async throws
}

nonisolated struct SystemMetricScheduler: MetricScheduler, Sendable {
    func wait(for interval: TimeInterval) async throws {
        let nanoseconds = UInt64(max(interval, 0) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

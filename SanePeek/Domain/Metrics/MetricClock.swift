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
        // `Task.sleep(nanoseconds:)` is a strict deadline that defeats the kernel's timer
        // coalescing, waking the CPU at the exact requested instant instead of letting it batch
        // this wakeup with other nearby ones. A tolerance of 10% of the interval (capped at 1s)
        // costs no perceptible accuracy on a 1-5s polling cadence but lets `Task.sleep(for:)`
        // opt into coalescing, which is the standard battery-friendly form (performance
        // review P5).
        let clamped = max(interval, 0)
        try await Task.sleep(
            for: .seconds(clamped),
            tolerance: .seconds(min(clamped * 0.1, 1))
        )
    }
}

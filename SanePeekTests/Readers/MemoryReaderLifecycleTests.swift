import Foundation
import Testing

@testable import SanePeek

@Suite("Memory reader lifecycle")
struct MemoryReaderLifecycleTests {
    @Test("Cancels the injected pressure source when the reader is released")
    func cancelsPressureSourceOnRelease() async {
        let pressureSource = TrackingMemoryPressureSource()
        var reader: LiveMemoryReader? = LiveMemoryReader(
            adapter: LifecycleMemoryAdapter(),
            pressureSource: pressureSource
        )

        #expect(pressureSource.startCount == 1)
        reader = nil

        #expect(pressureSource.cancelCount == 1)
    }
}

private final class TrackingMemoryPressureSource: MemoryPressureSource, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var cancels = 0

    var currentPressure: MemoryPressure? { nil }

    var startCount: Int {
        lock.withLock { starts }
    }

    var cancelCount: Int {
        lock.withLock { cancels }
    }

    func start() {
        lock.withLock { starts += 1 }
    }

    func cancel() {
        lock.withLock { cancels += 1 }
    }
}

private struct LifecycleMemoryAdapter: MemorySystemAdapter {
    func read(at timestamp: MetricTimestamp) -> MetricResult<MemorySystemSample> {
        .unavailable(.noData)
    }
}

import Foundation

nonisolated struct MetricSample<Value: Sendable & Equatable>: Sendable, Equatable {
    let timestamp: MetricTimestamp
    let value: Value

    init(timestamp: MetricTimestamp, value: Value) {
        self.timestamp = timestamp
        self.value = value
    }
}

nonisolated struct MetricRingBuffer<Value: Sendable & Equatable>: Sendable, Equatable {
    let retention: TimeInterval
    let capacity: Int

    private var storage: [MetricSample<Value>] = []

    init(retention: TimeInterval = 60, capacity: Int = 60) {
        self.retention = max(retention, 0)
        self.capacity = max(capacity, 1)
    }

    var samples: [MetricSample<Value>] {
        storage
    }

    var count: Int {
        storage.count
    }

    var oldest: MetricSample<Value>? {
        storage.first
    }

    var newest: MetricSample<Value>? {
        storage.last
    }

    @discardableResult
    mutating func append(_ sample: MetricSample<Value>) -> Bool {
        if let last = storage.last {
            if sample.timestamp.monotonicSeconds < last.timestamp.monotonicSeconds {
                return false
            }

            if sample.timestamp.monotonicSeconds == last.timestamp.monotonicSeconds {
                storage[storage.count - 1] = sample
                trim(through: sample.timestamp)
                return true
            }
        }

        storage.append(sample)
        trim(through: sample.timestamp)
        return true
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
    }

    /// `append` only ever accepts samples at or after the last one's timestamp, so `storage`
    /// stays sorted ascending — every sample old enough to drop is a prefix, never scattered
    /// through the array. That means the aged-out samples can be found with a linear scan from
    /// the front and dropped in one `removeFirst(_:)`, instead of `removeAll(where:)` visiting
    /// (and closure-calling on) every element on every append (performance review P9).
    private mutating func trim(through timestamp: MetricTimestamp) {
        let cutoff = timestamp.monotonicSeconds - retention
        var expiredCount = 0
        while expiredCount < storage.count, storage[expiredCount].timestamp.monotonicSeconds < cutoff {
            expiredCount += 1
        }
        if expiredCount > 0 {
            storage.removeFirst(expiredCount)
        }

        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }
}

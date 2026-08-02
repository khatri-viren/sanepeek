nonisolated struct MemoryPageCounts: Sendable, Equatable {
    let usedPages: UInt64
    let availablePages: UInt64

    init(usedPages: UInt64, availablePages: UInt64) {
        self.usedPages = usedPages
        self.availablePages = availablePages
    }
}

nonisolated enum MemoryByteConverter {
    static func bytes(
        from pages: UInt64,
        pageSize: UInt64
    ) -> MetricResult<UInt64> {
        guard pageSize > 0 else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (bytes, overflow) = pages.multipliedReportingOverflow(by: pageSize)
        guard !overflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(bytes)
    }

    static func snapshot(
        from pageCounts: MemoryPageCounts,
        pageSize: UInt64,
        timestamp: MetricTimestamp,
        pressure: MemoryPressure? = nil
    ) -> MetricResult<MemorySnapshot> {
        let usedBytes = bytes(from: pageCounts.usedPages, pageSize: pageSize)
        let availableBytes = bytes(from: pageCounts.availablePages, pageSize: pageSize)

        guard let used = usedBytes.value, let available = availableBytes.value else {
            if case let .failed(failure) = usedBytes {
                return .failed(failure)
            }
            if case let .failed(failure) = availableBytes {
                return .failed(failure)
            }
            return .unavailable(.noData)
        }

        return .available(
            MemorySnapshot(
                timestamp: timestamp,
                usedBytes: used,
                availableBytes: available,
                pressure: pressure
            )
        )
    }
}

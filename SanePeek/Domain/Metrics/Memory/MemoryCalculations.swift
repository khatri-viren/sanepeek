nonisolated struct MemoryPageCounts: Sendable, Equatable {
    let usedPages: UInt64
    let availablePages: UInt64
    let appPages: UInt64
    let wiredPages: UInt64
    let compressedPages: UInt64

    init(
        usedPages: UInt64,
        availablePages: UInt64,
        appPages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64
    ) {
        self.usedPages = usedPages
        self.availablePages = availablePages
        self.appPages = appPages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
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

        let breakdown = breakdownFractions(from: pageCounts, pageSize: pageSize, used: used, available: available)

        return .available(
            MemorySnapshot(
                timestamp: timestamp,
                usedBytes: used,
                availableBytes: available,
                pressure: pressure,
                appUtilization: breakdown?.app,
                wiredUtilization: breakdown?.wired,
                compressedUtilization: breakdown?.compressed
            )
        )
    }

    /// The App/Wired/Compressed breakdown is supplementary to `usedBytes`/`availableBytes`,
    /// so a failed sub-conversion or zero total degrades to `nil` for all three rather than
    /// failing the whole snapshot.
    private static func breakdownFractions(
        from pageCounts: MemoryPageCounts,
        pageSize: UInt64,
        used: UInt64,
        available: UInt64
    ) -> (app: Double, wired: Double, compressed: Double)? {
        let total = Double(used) + Double(available)
        guard total > 0,
              let appBytes = bytes(from: pageCounts.appPages, pageSize: pageSize).value,
              let wiredBytes = bytes(from: pageCounts.wiredPages, pageSize: pageSize).value,
              let compressedBytes = bytes(from: pageCounts.compressedPages, pageSize: pageSize).value
        else {
            return nil
        }

        return (
            app: Double(appBytes) / total,
            wired: Double(wiredBytes) / total,
            compressed: Double(compressedBytes) / total
        )
    }
}

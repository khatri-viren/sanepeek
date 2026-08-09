import Darwin
import Foundation
import IOKit
import IOKit.ps
import Network
import os

nonisolated protocol StorageReader: MetricReader where Snapshot == StorageSnapshot {}

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
    private let logger = Logger(subsystem: "com.sanepeek.app", category: "StorageReader")

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
                logger.warning("read failed: \(MetricFailureKind.invalidData.rawValue, privacy: .public)")
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
            logger.warning("read failed: \(failure.kind.rawValue, privacy: .public)")
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
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])

            // System Settings reports the space available for important usage, which includes
            // reclaimable APFS space. The generic capacity key is more conservative and can
            // under-report user-visible free space by several gigabytes.
            let availableBytes = values.volumeAvailableCapacityForImportantUsage
                ?? values.volumeAvailableCapacity.map { Int64($0) }
            return .available(
                StorageSystemSample(
                    totalBytes: values.volumeTotalCapacity.map(Int64.init),
                    availableBytes: availableBytes
                )
            )
        } catch {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }
    }
}

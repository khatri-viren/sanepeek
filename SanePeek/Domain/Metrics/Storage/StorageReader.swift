import Darwin
import Foundation
import IOKit
import IOKit.ps
import Network

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
                .volumeAvailableCapacityKey
            ])
            return .available(
                StorageSystemSample(
                    totalBytes: values.volumeTotalCapacity.map(Int64.init),
                    availableBytes: values.volumeAvailableCapacity.map(Int64.init)
                )
            )
        } catch {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }
    }
}

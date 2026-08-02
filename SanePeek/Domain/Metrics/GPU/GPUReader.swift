import Darwin
import Foundation
import IOKit
import IOKit.ps
import Network
import os

nonisolated protocol GPUReader: MetricReader where Snapshot == GPUSnapshot {}

nonisolated struct GPUCapability: Sendable, Equatable {
    let isSupported: Bool
    let name: String?

    init(isSupported: Bool, name: String? = nil) {
        self.isSupported = isSupported
        self.name = name
    }
}

nonisolated struct GPUSystemSample: Sendable, Equatable {
    let utilization: Double?
    let name: String?

    init(utilization: Double?, name: String? = nil) {
        self.utilization = utilization
        self.name = name
    }
}

nonisolated protocol GPUSystemAdapter: Sendable {
    var capability: GPUCapability { get }

    func read(at timestamp: MetricTimestamp) -> MetricResult<GPUSystemSample>
}

nonisolated struct LiveGPUReader: GPUReader {
    private let adapter: any GPUSystemAdapter
    private let logger = Logger(subsystem: "com.sanepeek.app", category: "GPUReader")

    init(adapter: any GPUSystemAdapter = IORegistryGPUAdapter()) {
        self.adapter = adapter
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<GPUSnapshot> {
        guard adapter.capability.isSupported else {
            return .unavailable(.unsupported)
        }

        switch adapter.read(at: timestamp) {
        case let .available(sample):
            if let utilization = sample.utilization {
                guard utilization.isFinite, (0...1).contains(utilization) else {
                    logger.warning("read failed: \(MetricFailureKind.invalidData.rawValue, privacy: .public)")
                    return .failed(MetricFailure(kind: .invalidData))
                }
            }

            return .available(
                GPUSnapshot(
                    timestamp: timestamp,
                    utilization: sample.utilization,
                    name: sample.name ?? adapter.capability.name
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

nonisolated struct IORegistryGPUAdapter: GPUSystemAdapter {
    let capability: GPUCapability

    init() {
        capability = Self.discoverCapability()
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<GPUSystemSample> {
        .unavailable(.unsupported)
    }

    private static func discoverCapability() -> GPUCapability {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator"),
              IOServiceGetMatchingServices(
                kIOMainPortDefault,
                matching,
                &iterator
              ) == KERN_SUCCESS
        else {
            return GPUCapability(isSupported: false)
        }
        defer {
            IOObjectRelease(iterator)
        }

        var discoveredName: String?
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else {
                break
            }
            defer {
                IOObjectRelease(service)
            }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            let result = nameBuffer.withUnsafeMutableBufferPointer { buffer in
                IORegistryEntryGetName(service, buffer.baseAddress!)
            }
            if result == KERN_SUCCESS {
                let nameBytes = nameBuffer
                    .prefix(while: { $0 != 0 })
                    .map { UInt8(bitPattern: $0) }
                let name = String(decoding: nameBytes, as: UTF8.self)
                if !name.isEmpty {
                    discoveredName = name
                    break
                }
            }
        }

        return GPUCapability(isSupported: false, name: discoveredName)
    }
}

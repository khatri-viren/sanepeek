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
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator"),
              IOServiceGetMatchingServices(
                  kIOMainPortDefault,
                  matching,
                  &iterator
              ) == KERN_SUCCESS
        else {
            return .unavailable(.temporarilyUnavailable)
        }
        defer {
            IOObjectRelease(iterator)
        }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else {
                break
            }
            defer {
                IOObjectRelease(service)
            }

            guard let properties = Self.properties(for: service),
                  let statistics = properties["PerformanceStatistics"] as? [String: Any],
                  let percent = Self.number(from: statistics["Device Utilization %"]),
                  let utilization = Self.utilizationFraction(fromPercent: percent)
            else {
                continue
            }

            return .available(
                GPUSystemSample(
                    utilization: utilization,
                    name: Self.name(for: service) ?? capability.name
                )
            )
        }

        return .unavailable(.temporarilyUnavailable)
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

            if let name = Self.name(for: service) {
                discoveredName = name
            }

            guard let properties = Self.properties(for: service),
                  let statistics = properties["PerformanceStatistics"] as? [String: Any],
                  Self.number(from: statistics["Device Utilization %"]) != nil
            else {
                continue
            }

            return GPUCapability(isSupported: true, name: discoveredName)
        }

        return GPUCapability(isSupported: false, name: discoveredName)
    }

    private static func properties(for service: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanaged,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let unmanaged,
        let properties = unmanaged.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        return properties
    }

    private static func name(for service: io_registry_entry_t) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: 128)
        let result = nameBuffer.withUnsafeMutableBufferPointer { buffer in
            IORegistryEntryGetName(service, buffer.baseAddress!)
        }
        guard result == KERN_SUCCESS else {
            return nil
        }

        let nameBytes = nameBuffer
            .prefix(while: { $0 != 0 })
            .map { UInt8(bitPattern: $0) }
        let name = String(decoding: nameBytes, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }

    static func utilizationFraction(fromPercent percent: Double) -> Double? {
        guard percent.isFinite, (0...100).contains(percent) else {
            return nil
        }
        return percent / 100
    }
}

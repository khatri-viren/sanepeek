import Darwin
import Foundation
import IOKit
import IOKit.ps
import Network
import os

nonisolated protocol MemoryReader: MetricReader where Snapshot == MemorySnapshot {}

nonisolated struct MemorySystemSample: Sendable, Equatable {
    let pageCounts: MemoryPageCounts
    let pageSize: UInt64

    init(pageCounts: MemoryPageCounts, pageSize: UInt64) {
        self.pageCounts = pageCounts
        self.pageSize = pageSize
    }
}

nonisolated protocol MemorySystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<MemorySystemSample>
}

nonisolated protocol MemoryPressureSource: Sendable {
    var currentPressure: MemoryPressure? { get }

    func start()
    func cancel()
}

actor LiveMemoryReader: MemoryReader {
    private let adapter: any MemorySystemAdapter
    private let pressureSource: any MemoryPressureSource
    private let logger = Logger(subsystem: "com.sanepeek.app", category: "MemoryReader")

    init(
        adapter: any MemorySystemAdapter = MachMemorySystemAdapter(),
        pressureSource: any MemoryPressureSource = DispatchMemoryPressureSource()
    ) {
        self.adapter = adapter
        self.pressureSource = pressureSource
        pressureSource.start()
    }

    deinit {
        pressureSource.cancel()
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<MemorySnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            return MemoryByteConverter.snapshot(
                from: sample.pageCounts,
                pageSize: sample.pageSize,
                timestamp: timestamp,
                pressure: pressureSource.currentPressure
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            logger.warning("read failed: \(failure.kind.rawValue, privacy: .public)")
            return .failed(failure)
        }
    }
}

nonisolated struct MachMemorySystemAdapter: MemorySystemAdapter {
    init() {}

    func read(at timestamp: MetricTimestamp) -> MetricResult<MemorySystemSample> {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }

        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    info,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }

        guard let usedPages = sumPages([
            UInt64(statistics.active_count),
            UInt64(statistics.inactive_count),
            UInt64(statistics.wire_count),
            UInt64(statistics.compressor_page_count)
        ]), let availablePages = sumPages([
            UInt64(statistics.free_count),
            UInt64(statistics.speculative_count)
        ]) else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(
            MemorySystemSample(
                pageCounts: MemoryPageCounts(
                    usedPages: usedPages,
                    availablePages: availablePages
                ),
                pageSize: UInt64(pageSize)
            )
        )
    }

    private func sumPages(_ values: [UInt64]) -> UInt64? {
        values.reduce(into: UInt64(0)) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            total = overflow ? UInt64.max : sum
        }
    }
}

final class DispatchMemoryPressureSource: MemoryPressureSource, @unchecked Sendable {
    private let lock = NSLock()
    private let source: DispatchSourceMemoryPressure
    private var started = false
    private var cancelled = false
    private var pressure: MemoryPressure?

    init(queue: DispatchQueue = DispatchQueue(label: "com.sanepeek.memory-pressure", qos: .utility)) {
        let pressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: queue
        )
        source = pressureSource
        pressureSource.setEventHandler { [weak self, pressureSource] in
            self?.update(pressureSource.data)
        }
        start()
    }

    var currentPressure: MemoryPressure? {
        lock.lock()
        defer { lock.unlock() }
        return pressure
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started, !cancelled else { return }
        source.resume()
        started = true
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        lock.unlock()
        source.cancel()
    }

    deinit {
        cancel()
    }

    private func update(_ event: DispatchSource.MemoryPressureEvent) {
        let nextPressure: MemoryPressure
        if event.contains(.critical) {
            nextPressure = .critical
        } else if event.contains(.warning) {
            nextPressure = .warning
        } else {
            nextPressure = .normal
        }

        lock.lock()
        pressure = nextPressure
        lock.unlock()
    }
}

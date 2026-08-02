import Darwin
import Foundation
import IOKit
import IOKit.ps
import Network

nonisolated protocol CPUReader: MetricReader where Snapshot == CPUSnapshot {}

nonisolated struct CPUHardwareInfo: Sendable, Equatable {
    let logicalCoreCount: Int?
    let performanceCoreCount: Int?
    let efficiencyCoreCount: Int?

    init(
        logicalCoreCount: Int? = nil,
        performanceCoreCount: Int? = nil,
        efficiencyCoreCount: Int? = nil
    ) {
        self.logicalCoreCount = logicalCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
    }
}

nonisolated struct CPUSystemSample: Sendable, Equatable {
    let counter: CPUCounterSample
    let hardware: CPUHardwareInfo

    init(counter: CPUCounterSample, hardware: CPUHardwareInfo = .init()) {
        self.counter = counter
        self.hardware = hardware
    }
}

nonisolated protocol CPUSystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<CPUSystemSample>
}

actor LiveCPUReader: CPUReader {
    private let adapter: any CPUSystemAdapter
    private let counterMaximum: UInt64?
    private var previousCounter: CPUCounterSample?

    init(
        adapter: any CPUSystemAdapter = MachCPUSystemAdapter(),
        counterMaximum: UInt64? = nil
    ) {
        self.adapter = adapter
        self.counterMaximum = counterMaximum
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<CPUSnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            let utilization = previousCounter.map { previous in
                CPUUtilizationCalculator.calculate(
                    from: previous,
                    to: sample.counter,
                    counterMaximum: counterMaximum
                ).value
            } ?? nil
            previousCounter = sample.counter

            return .available(
                CPUSnapshot(
                    timestamp: timestamp,
                    utilization: utilization,
                    logicalCoreCount: sample.hardware.logicalCoreCount,
                    performanceCoreCount: sample.hardware.performanceCoreCount,
                    efficiencyCoreCount: sample.hardware.efficiencyCoreCount
                )
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            return .failed(failure)
        }
    }
}

nonisolated struct MachCPUSystemAdapter: CPUSystemAdapter {
    init() {}

    func read(at timestamp: MetricTimestamp) -> MetricResult<CPUSystemSample> {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS else {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }

        guard let processorInfo else {
            return .unavailable(.noData)
        }

        let allocatedBytes = vm_size_t(
            Int(processorInfoCount) * MemoryLayout<natural_t>.stride
        )
        defer {
            _ = vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: processorInfo)),
                allocatedBytes
            )
        }

        let ticksPerProcessor = MemoryLayout<processor_cpu_load_info_data_t>.size
            / MemoryLayout<natural_t>.size
        let availableProcessorCount = min(
            Int(processorCount),
            Int(processorInfoCount) / ticksPerProcessor
        )

        guard availableProcessorCount > 0 else {
            return .unavailable(.noData)
        }

        let aggregateCounter: CPUCounterSample? = processorInfo.withMemoryRebound(
            to: processor_cpu_load_info_data_t.self,
            capacity: availableProcessorCount
        ) { loadInfo in
            var userTicks: UInt64 = 0
            var systemTicks: UInt64 = 0
            var idleTicks: UInt64 = 0
            var niceTicks: UInt64 = 0

            for index in 0..<availableProcessorCount {
                let ticks = loadInfo[index].cpu_ticks
                let (newUserTicks, userOverflow) = userTicks.addingReportingOverflow(UInt64(ticks.0))
                let (newSystemTicks, systemOverflow) = systemTicks.addingReportingOverflow(UInt64(ticks.1))
                let (newIdleTicks, idleOverflow) = idleTicks.addingReportingOverflow(UInt64(ticks.2))
                let (newNiceTicks, niceOverflow) = niceTicks.addingReportingOverflow(UInt64(ticks.3))

                guard !userOverflow, !systemOverflow, !idleOverflow, !niceOverflow else {
                    return nil
                }

                userTicks = newUserTicks
                systemTicks = newSystemTicks
                idleTicks = newIdleTicks
                niceTicks = newNiceTicks
            }

            return CPUCounterSample(
                timestamp: timestamp,
                userTicks: userTicks,
                systemTicks: systemTicks,
                idleTicks: idleTicks,
                niceTicks: niceTicks
            )
        }

        guard let aggregateCounter else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let logicalCoreCount = ProcessInfo.processInfo.processorCount
        let hardware = CPUHardwareInfo(
            logicalCoreCount: logicalCoreCount > 0 ? logicalCoreCount : nil,
            performanceCoreCount: readSysctlInt32(named: "hw.perflevel0.logicalcpu"),
            efficiencyCoreCount: readSysctlInt32(named: "hw.perflevel1.logicalcpu")
        )

        return .available(CPUSystemSample(counter: aggregateCounter, hardware: hardware))
    }

    private func readSysctlInt32(named name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = name.withCString {
            sysctlbyname($0, &value, &size, nil, 0)
        }

        guard result == 0, value > 0 else {
            return nil
        }
        return Int(value)
    }
}

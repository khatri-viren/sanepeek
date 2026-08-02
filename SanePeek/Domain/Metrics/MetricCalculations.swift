import Foundation

nonisolated struct CPUCounterSample: Sendable, Equatable {
    let timestamp: MetricTimestamp
    let userTicks: UInt64
    let systemTicks: UInt64
    let idleTicks: UInt64
    let niceTicks: UInt64

    init(
        timestamp: MetricTimestamp,
        userTicks: UInt64,
        systemTicks: UInt64,
        idleTicks: UInt64,
        niceTicks: UInt64 = 0
    ) {
        self.timestamp = timestamp
        self.userTicks = userTicks
        self.systemTicks = systemTicks
        self.idleTicks = idleTicks
        self.niceTicks = niceTicks
    }
}

nonisolated enum MetricCounterDeltaCalculator {
    static func calculate(
        from previous: UInt64,
        to current: UInt64,
        counterMaximum: UInt64? = nil
    ) -> MetricResult<UInt64> {
        if current >= previous {
            return .available(current - previous)
        }

        guard let counterMaximum else {
            return .unavailable(.noData)
        }

        guard previous <= counterMaximum, current <= counterMaximum else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (distanceToMaximum, firstOverflow) = counterMaximum
            .subtractingReportingOverflow(previous)
        guard !firstOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (wrappedDistance, secondOverflow) = distanceToMaximum
            .addingReportingOverflow(1)
        guard !secondOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (delta, thirdOverflow) = wrappedDistance.addingReportingOverflow(current)
        guard !thirdOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(delta)
    }
}

nonisolated enum CPUUtilizationCalculator {
    static func calculate(
        from previous: CPUCounterSample,
        to current: CPUCounterSample,
        counterMaximum: UInt64? = nil
    ) -> MetricResult<Double> {
        let duration = current.timestamp.monotonicSeconds - previous.timestamp.monotonicSeconds
        guard duration.isFinite, duration > 0 else {
            return .unavailable(.noData)
        }

        let deltas = [
            MetricCounterDeltaCalculator.calculate(
                from: previous.userTicks,
                to: current.userTicks,
                counterMaximum: counterMaximum
            ),
            MetricCounterDeltaCalculator.calculate(
                from: previous.systemTicks,
                to: current.systemTicks,
                counterMaximum: counterMaximum
            ),
            MetricCounterDeltaCalculator.calculate(
                from: previous.idleTicks,
                to: current.idleTicks,
                counterMaximum: counterMaximum
            ),
            MetricCounterDeltaCalculator.calculate(
                from: previous.niceTicks,
                to: current.niceTicks,
                counterMaximum: counterMaximum
            )
        ]

        guard let values = availableValues(from: deltas) else {
            return unavailableOrFailed(from: deltas)
        }

        let (activeTicks, activeOverflow) = values[0]
            .addingReportingOverflow(values[1])
        guard !activeOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (activeWithNiceTicks, niceOverflow) = activeTicks
            .addingReportingOverflow(values[3])
        guard !niceOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        let (totalTicks, totalOverflow) = activeWithNiceTicks
            .addingReportingOverflow(values[2])
        guard !totalOverflow else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        guard totalTicks > 0 else {
            return .unavailable(.noData)
        }

        let utilization = Double(activeWithNiceTicks) / Double(totalTicks)
        guard utilization.isFinite else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(min(max(utilization, 0), 1))
    }

    private static func availableValues(
        from results: [MetricResult<UInt64>]
    ) -> [UInt64]? {
        var values: [UInt64] = []
        values.reserveCapacity(results.count)

        for result in results {
            guard case let .available(value) = result else {
                return nil
            }
            values.append(value)
        }

        return values
    }

    private static func unavailableOrFailed(
        from results: [MetricResult<UInt64>]
    ) -> MetricResult<Double> {
        for result in results {
            if case let .failed(failure) = result {
                return .failed(failure)
            }
        }
        return .unavailable(.noData)
    }
}

nonisolated struct NetworkInterfaceCounter: Sendable, Equatable {
    let name: String
    let downloadBytes: UInt64
    let uploadBytes: UInt64
    let isLoopback: Bool
    let isValid: Bool

    init(
        name: String,
        downloadBytes: UInt64,
        uploadBytes: UInt64,
        isLoopback: Bool = false,
        isValid: Bool = true
    ) {
        self.name = name
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
        self.isLoopback = isLoopback
        self.isValid = isValid
    }
}

nonisolated struct NetworkCounterSample: Sendable, Equatable {
    let timestamp: MetricTimestamp
    let interfaces: [NetworkInterfaceCounter]

    init(timestamp: MetricTimestamp, interfaces: [NetworkInterfaceCounter]) {
        self.timestamp = timestamp
        self.interfaces = interfaces
    }
}

nonisolated struct NetworkThroughput: Sendable, Equatable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double

    init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

nonisolated enum NetworkThroughputCalculator {
    static func calculate(
        from previous: NetworkCounterSample,
        to current: NetworkCounterSample,
        counterMaximum: UInt64? = nil
    ) -> MetricResult<NetworkThroughput> {
        let duration = current.timestamp.monotonicSeconds - previous.timestamp.monotonicSeconds
        guard duration.isFinite, duration > 0 else {
            return .unavailable(.noData)
        }

        let previousInterfaces = validInterfaces(from: previous)
        let currentInterfaces = validInterfaces(from: current)
        var totalDownloadBytes: UInt64 = 0
        var totalUploadBytes: UInt64 = 0
        var matchedInterfaceCount = 0

        for name in currentInterfaces.keys.sorted() {
            guard let currentInterface = currentInterfaces[name],
                  let previousInterface = previousInterfaces[name]
            else {
                continue
            }

            let download = MetricCounterDeltaCalculator.calculate(
                from: previousInterface.downloadBytes,
                to: currentInterface.downloadBytes,
                counterMaximum: counterMaximum
            )
            let upload = MetricCounterDeltaCalculator.calculate(
                from: previousInterface.uploadBytes,
                to: currentInterface.uploadBytes,
                counterMaximum: counterMaximum
            )

            guard let downloadBytes = download.value,
                  let uploadBytes = upload.value
            else {
                if case let .failed(failure) = download {
                    return .failed(failure)
                }
                if case let .failed(failure) = upload {
                    return .failed(failure)
                }
                continue
            }

            let (newDownloadTotal, downloadOverflow) = totalDownloadBytes
                .addingReportingOverflow(downloadBytes)
            let (newUploadTotal, uploadOverflow) = totalUploadBytes
                .addingReportingOverflow(uploadBytes)
            guard !downloadOverflow, !uploadOverflow else {
                return .failed(MetricFailure(kind: .invalidData))
            }

            totalDownloadBytes = newDownloadTotal
            totalUploadBytes = newUploadTotal
            matchedInterfaceCount += 1
        }

        guard matchedInterfaceCount > 0 else {
            return .unavailable(.noData)
        }

        let downloadRate = Double(totalDownloadBytes) / duration
        let uploadRate = Double(totalUploadBytes) / duration
        guard downloadRate.isFinite, uploadRate.isFinite else {
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(
            NetworkThroughput(
                downloadBytesPerSecond: downloadRate,
                uploadBytesPerSecond: uploadRate
            )
        )
    }

    private static func validInterfaces(
        from sample: NetworkCounterSample
    ) -> [String: NetworkInterfaceCounter] {
        var result: [String: NetworkInterfaceCounter] = [:]

        for interface in sample.interfaces where
            interface.isValid && !interface.isLoopback && !interface.name.isEmpty
        {
            if result[interface.name] == nil {
                result[interface.name] = interface
            }
        }

        return result
    }
}

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

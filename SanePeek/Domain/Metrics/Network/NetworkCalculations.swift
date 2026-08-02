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

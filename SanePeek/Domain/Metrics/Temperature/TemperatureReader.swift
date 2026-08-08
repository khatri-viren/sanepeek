import Foundation
import os

nonisolated protocol TemperatureReader: MetricReader where Snapshot == TemperatureSnapshot {}

nonisolated struct TemperatureSystemSample: Sendable, Equatable {
    let cpuCelsius: Double?
    let gpuCelsius: Double?

    init(cpuCelsius: Double?, gpuCelsius: Double?) {
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
    }
}

nonisolated protocol TemperatureSystemAdapter: Sendable {
    /// False when this Mac exposes no readable sensor — either genuinely (an unknown model)
    /// or because the process is sandboxed and the SMC user client was refused.
    var isSupported: Bool { get }

    func read(at timestamp: MetricTimestamp) -> MetricResult<TemperatureSystemSample>
}

/// Real CPU/GPU die temperature, read from the SMC through public IOKit calls.
///
/// This requires an unsandboxed process: `SMCTemperatureAdapter` degrades to
/// `isSupported == false` under the App Sandbox, so a sandboxed build of the same source
/// keeps reporting "unavailable" rather than misreporting. See
/// `plans/sanepeek-temperature-plan.md` in the vault for the measurement behind that split.
nonisolated struct LiveTemperatureReader: TemperatureReader {
    private let adapter: any TemperatureSystemAdapter
    private let logger = Logger(subsystem: "com.sanepeek.app", category: "TemperatureReader")

    init(adapter: any TemperatureSystemAdapter = SMCTemperatureAdapter()) {
        self.adapter = adapter
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<TemperatureSnapshot> {
        guard adapter.isSupported else {
            return .unavailable(.unsupported)
        }

        switch adapter.read(at: timestamp) {
        case let .available(sample):
            for value in [sample.cpuCelsius, sample.gpuCelsius].compactMap({ $0 }) {
                guard SMCSensorKeys.isPlausible(value) else {
                    logger.warning("read failed: \(MetricFailureKind.invalidData.rawValue, privacy: .public)")
                    return .failed(MetricFailure(kind: .invalidData))
                }
            }

            guard sample.cpuCelsius != nil || sample.gpuCelsius != nil else {
                return .unavailable(.noData)
            }

            return .available(
                TemperatureSnapshot(
                    timestamp: timestamp,
                    cpuCelsius: sample.cpuCelsius,
                    gpuCelsius: sample.gpuCelsius
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

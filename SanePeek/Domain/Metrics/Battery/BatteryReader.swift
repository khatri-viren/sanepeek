import Darwin
import Foundation
import IOKit
import IOKit.ps
import Network
import os

nonisolated protocol BatteryReader: MetricReader where Snapshot == BatterySnapshot {}

nonisolated enum BatteryPowerSourceState: Sendable, Equatable {
    case ac
    case battery
    case offline
    case unknown
}

nonisolated struct BatterySystemSample: Sendable, Equatable {
    let isPresent: Bool
    let currentCapacity: Int64?
    let maximumCapacity: Int64?
    let isCharging: Bool?
    let powerSourceState: BatteryPowerSourceState
    let timeToEmptyMinutes: Int64?
    let timeToFullChargeMinutes: Int64?
    let designCapacity: Int64?

    init(
        isPresent: Bool,
        currentCapacity: Int64?,
        maximumCapacity: Int64?,
        isCharging: Bool?,
        powerSourceState: BatteryPowerSourceState = .unknown,
        timeToEmptyMinutes: Int64?,
        timeToFullChargeMinutes: Int64?,
        designCapacity: Int64?
    ) {
        self.isPresent = isPresent
        self.currentCapacity = currentCapacity
        self.maximumCapacity = maximumCapacity
        self.isCharging = isCharging
        self.powerSourceState = powerSourceState
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.designCapacity = designCapacity
    }
}

nonisolated protocol BatterySystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<BatterySystemSample>
}

nonisolated struct LiveBatteryReader: BatteryReader {
    private let adapter: any BatterySystemAdapter
    private let logger = Logger(subsystem: "com.sanepeek.app", category: "BatteryReader")

    init(adapter: any BatterySystemAdapter = IOKitBatterySystemAdapter()) {
        self.adapter = adapter
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<BatterySnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            guard sample.isPresent else {
                return .unavailable(.notPresent)
            }

            let percentage: Double?
            if let currentCapacity = sample.currentCapacity,
               let maximumCapacity = sample.maximumCapacity
            {
                guard currentCapacity >= 0,
                      maximumCapacity > 0,
                      currentCapacity <= maximumCapacity
                else {
                    logger.warning("read failed: \(MetricFailureKind.invalidData.rawValue, privacy: .public)")
                    return .failed(MetricFailure(kind: .invalidData))
                }
                percentage = Double(currentCapacity) / Double(maximumCapacity)
            } else {
                percentage = nil
            }

            let healthPercentage: Double?
            if let designCapacity = sample.designCapacity {
                guard designCapacity > 0 else {
                    logger.warning("read failed: \(MetricFailureKind.invalidData.rawValue, privacy: .public)")
                    return .failed(MetricFailure(kind: .invalidData))
                }

                if let maximumCapacity = sample.maximumCapacity {
                    guard maximumCapacity >= 0 else {
                        logger.warning("read failed: \(MetricFailureKind.invalidData.rawValue, privacy: .public)")
                        return .failed(MetricFailure(kind: .invalidData))
                    }
                    healthPercentage = min(
                        max(Double(maximumCapacity) / Double(designCapacity), 0),
                        1
                    )
                } else {
                    healthPercentage = nil
                }
            } else {
                healthPercentage = nil
            }

            let chargingState = chargingState(for: sample)
            let timeRemaining = timeRemaining(for: sample)

            return .available(
                BatterySnapshot(
                    timestamp: timestamp,
                    percentage: percentage,
                    chargingState: chargingState,
                    timeRemaining: timeRemaining,
                    healthPercentage: healthPercentage
                )
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            logger.warning("read failed: \(failure.kind.rawValue, privacy: .public)")
            return .failed(failure)
        }
    }

    private func chargingState(for sample: BatterySystemSample) -> BatteryChargingState {
        if sample.isCharging == true {
            return .charging
        }

        if let currentCapacity = sample.currentCapacity,
           let maximumCapacity = sample.maximumCapacity,
           maximumCapacity > 0,
           currentCapacity >= maximumCapacity
        {
            return .charged
        }

        switch sample.powerSourceState {
        case .battery:
            return .unplugged
        case .ac:
            return .charged
        case .offline, .unknown:
            return .unknown
        }
    }

    private func timeRemaining(for sample: BatterySystemSample) -> TimeInterval? {
        let minutes = sample.isCharging == true
            ? sample.timeToFullChargeMinutes
            : sample.timeToEmptyMinutes

        guard let minutes, minutes >= 0 else {
            return nil
        }

        return TimeInterval(minutes) * 60
    }
}

nonisolated struct IOKitBatterySystemAdapter: BatterySystemAdapter {
    private enum Key {
        static let currentCapacity = "Current Capacity"
        static let designCapacity = "DesignCapacity"
        static let isCharging = "Is Charging"
        static let isPresent = "Is Present"
        static let maxCapacity = "Max Capacity"
        static let powerSourceState = "Power Source State"
        static let timeToEmpty = "Time to Empty"
        static let timeToFullCharge = "Time to Full Charge"
        static let transportType = "Transport Type"
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<BatterySystemSample> {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unavailable(.notPresent)
        }

        let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo).takeRetainedValue()
        let count = CFArrayGetCount(powerSources)
        guard count > 0 else {
            return .unavailable(.notPresent)
        }

        var nonPresentBattery: BatterySystemSample?

        for index in 0..<count {
            let powerSource = CFArrayGetValueAtIndex(powerSources, index)
            guard let powerSource else {
                continue
            }

            let powerSourceRef = Unmanaged<CFTypeRef>
                .fromOpaque(powerSource)
                .takeUnretainedValue()
            guard
                  let description = IOPSGetPowerSourceDescription(
                    powerSourcesInfo,
                    powerSourceRef
                  )?.takeUnretainedValue()
            else {
                continue
            }

            let dictionary = description as NSDictionary
            guard let transportType = dictionary[Key.transportType] as? String,
                  transportType == "InternalBattery"
            else {
                continue
            }

            let sample = BatterySystemSample(
                isPresent: number(in: dictionary, for: Key.isPresent)?.boolValue ?? false,
                currentCapacity: number(in: dictionary, for: Key.currentCapacity)?.int64Value,
                maximumCapacity: number(in: dictionary, for: Key.maxCapacity)?.int64Value,
                isCharging: number(in: dictionary, for: Key.isCharging)?.boolValue,
                powerSourceState: powerSourceState(
                    from: dictionary[Key.powerSourceState] as? String
                ),
                timeToEmptyMinutes: number(in: dictionary, for: Key.timeToEmpty)?.int64Value,
                timeToFullChargeMinutes: number(in: dictionary, for: Key.timeToFullCharge)?.int64Value,
                designCapacity: number(in: dictionary, for: Key.designCapacity)?.int64Value
            )

            if sample.isPresent {
                return .available(sample)
            }
            nonPresentBattery = sample
        }

        if let nonPresentBattery {
            return .available(nonPresentBattery)
        }
        return .unavailable(.notPresent)
    }

    private func number(in dictionary: NSDictionary, for key: String) -> NSNumber? {
        dictionary[key] as? NSNumber
    }

    private func powerSourceState(from value: String?) -> BatteryPowerSourceState {
        switch value {
        case "AC Power":
            .ac
        case "Battery Power":
            .battery
        case "Off Line":
            .offline
        default:
            .unknown
        }
    }
}

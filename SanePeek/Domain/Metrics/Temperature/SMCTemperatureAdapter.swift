import Foundation
import IOKit
import os

/// Reads CPU/GPU die temperatures from the SMC.
///
/// This uses only public IOKit (`IOServiceOpen`, `IOConnectCallStructMethod`) — no private
/// framework is linked or `dlsym`'d, so PRD §15's "do not use private frameworks" rule holds.
/// What it *does* require is that the process is not sandboxed: under the App Sandbox the
/// `IOServiceOpen` below fails with `kIOReturnNotPermitted` (0xe00002e2), measured on
/// 2026-08-08. That is why real temperature ships in the direct-download build only; see
/// `plans/sanepeek-temperature-plan.md` in the vault.
///
/// `@unchecked Sendable` because `io_connect_t` carries no Sendable annotation; every use of
/// the connection is serialised by `lock`, matching `SCDynamicStorePrimaryInterfaceSource`.
nonisolated final class SMCTemperatureAdapter: TemperatureSystemAdapter, @unchecked Sendable {
    private struct Sensor {
        let key: UInt32
        let component: TemperatureComponent
        let keyInfo: SMCKeyInfoData
    }

    private let lock = NSLock()
    private let connection: io_connect_t
    private let sensors: [Sensor]
    private let logger = Logger(subsystem: "com.sanepeek.app", category: "SMCTemperature")

    /// Sensors whose type or size the SMC reports are resolved once here rather than on every
    /// sample. A naive implementation costs two `IOConnectCallStructMethod` round trips per key
    /// per tick; caching the key info halves that, which matters because this runs inside the
    /// idle-cost budget tuned in the performance review.
    init() {
        var connection: io_connect_t = 0
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            self.connection = 0
            sensors = []
            return
        }
        defer {
            IOObjectRelease(service)
        }

        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            self.connection = 0
            sensors = []
            return
        }
        self.connection = connection

        // Discovery returns keys normalized to their live-reading variants; see
        // `SMCSensorKeys.instantaneousKey(for:)` for why the advertised ones are wrong.
        let candidates = Self.discoverSensorKeys()
        sensors = candidates.compactMap { key -> Sensor? in
            guard let component = SMCSensorKeys.component(for: key),
                  let code = Self.fourCharCode(key),
                  let keyInfo = Self.keyInfo(for: code, connection: connection)
            else {
                return nil
            }
            return Sensor(key: code, component: component, keyInfo: keyInfo)
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    var isSupported: Bool {
        !sensors.isEmpty
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<TemperatureSystemSample> {
        guard isSupported else {
            return .unavailable(.unsupported)
        }

        var cpuReadings: [Double] = []
        var gpuReadings: [Double] = []

        lock.lock()
        for sensor in sensors {
            guard let value = Self.readValue(sensor, connection: connection) else {
                continue
            }
            switch sensor.component {
            case .cpu:
                cpuReadings.append(value)
            case .gpu:
                gpuReadings.append(value)
            }
        }
        lock.unlock()

        let cpu = SMCSensorKeys.hottest(of: cpuReadings)
        let gpu = SMCSensorKeys.hottest(of: gpuReadings)

        // Sensors were present at init but every read failed — the SMC is there and refusing,
        // which is a failure to report rather than an unsupported machine.
        guard cpu != nil || gpu != nil else {
            logger.warning("all \(self.sensors.count, privacy: .public) SMC sensors returned no plausible value")
            return .failed(MetricFailure(kind: .invalidData))
        }

        return .available(TemperatureSystemSample(cpuCelsius: cpu, gpuCelsius: gpu))
    }

    // MARK: - Sensor discovery

    /// Asks the machine which temperature sensors it has and falls back to a union catalog when
    /// the node is absent or contains no usable temperature keys. This keeps working across
    /// M-series generations and Intel without making the model identifier the source of truth.
    private static func discoverSensorKeys() -> [String] {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceNameMatching("smctempsensor0")
        )
        guard service != 0 else {
            return SMCSensorKeys.fallbackKeys
        }
        defer {
            IOObjectRelease(service)
        }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else {
            return SMCSensorKeys.fallbackKeys
        }

        // The property is published as raw bytes holding ASCII, not as a CFString.
        let blob: String?
        switch properties["sensor"] {
        case let data as Data:
            blob = String(decoding: data, as: UTF8.self)
        case let string as String:
            blob = string
        default:
            blob = nil
        }

        guard let blob else {
            return SMCSensorKeys.fallbackKeys
        }

        let discovered = SMCSensorKeys.parse(sensorProperty: blob)
        return SMCSensorKeys.candidates(from: discovered)
    }

    // MARK: - SMC protocol

    private static func fourCharCode(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == SMCSensorKeys.keyLength else {
            return nil
        }
        return bytes.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
    }

    private static func typeString(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func callSMC(
        _ input: inout SMCKeyData,
        _ output: inout SMCKeyData,
        connection: io_connect_t
    ) -> Bool {
        let size = MemoryLayout<SMCKeyData>.stride
        var outputSize = size
        let status = IOConnectCallStructMethod(
            connection,
            SMCSelector.handleYPCEvent,
            &input,
            size,
            &output,
            &outputSize
        )
        return status == KERN_SUCCESS && output.result == 0
    }

    private static func keyInfo(for key: UInt32, connection: io_connect_t) -> SMCKeyInfoData? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key
        input.data8 = SMCSelector.getKeyInfo
        guard callSMC(&input, &output, connection: connection) else {
            return nil
        }
        // Only the encodings `SMCSensorKeys.decode` understands are worth keeping.
        let type = typeString(output.keyInfo.dataType)
        guard type == "flt " || type == "sp78" else {
            return nil
        }
        return output.keyInfo
    }

    private static func readValue(_ sensor: Sensor, connection: io_connect_t) -> Double? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = sensor.key
        input.keyInfo = sensor.keyInfo
        input.data8 = SMCSelector.readKey
        guard callSMC(&input, &output, connection: connection) else {
            return nil
        }

        let size = Int(sensor.keyInfo.dataSize)
        guard size > 0, size <= MemoryLayout<SMCBytes>.size else {
            return nil
        }

        var payload = output.bytes
        let bytes = withUnsafeBytes(of: &payload) { Array($0.prefix(size)) }
        guard let value = SMCSensorKeys.decode(bytes, type: typeString(sensor.keyInfo.dataType)),
              SMCSensorKeys.isPlausible(value)
        else {
            return nil
        }
        return value
    }
}

// MARK: - SMC wire format

/// Selectors accepted by the AppleSMC user client's `handleYPCEvent` struct method.
private nonisolated enum SMCSelector {
    static let handleYPCEvent: UInt32 = 2
    static let readKey: UInt8 = 5
    static let getKeyInfo: UInt8 = 9
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

nonisolated struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

nonisolated struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

nonisolated struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

/// Mirrors the `SMCKeyData_t` layout the AppleSMC user client expects. Field order and the
/// explicit padding are load-bearing — this struct is copied verbatim across the IOKit
/// boundary, so it must not be reordered.
nonisolated struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

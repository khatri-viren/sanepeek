import Foundation

nonisolated enum TemperatureComponent: Equatable, Sendable {
    case cpu
    case gpu
}

/// Pure decoding and classification for the SMC's four-character sensor keys, kept free of
/// IOKit so it can be tested without the hardware it describes. `SMCTemperatureAdapter` owns
/// the actual user-client plumbing.
///
/// The key *names* are the only undocumented part of the SMC path — the calls that read them
/// (`IOServiceOpen`, `IOConnectCallStructMethod`) are public IOKit. Rather than hardcoding a
/// per-model key list, the adapter asks the machine which sensors it has (see
/// `parse(sensorProperty:)`) and this type decides what each one measures.
nonisolated enum SMCSensorKeys {
    static let keyLength = 4

    /// Temperatures outside this range are treated as a misread rather than a real reading:
    /// unpopulated SMC keys commonly return 0, and no sensor in a Mac legitimately reports
    /// above 150 °C.
    static let plausibleRange: ClosedRange<Double> = 1...150

    /// Splits the `sensor` property published by the `smctempsensor0` IORegistry node into
    /// individual keys. The property is a single run-together ASCII blob — on an M1 it reads
    /// `mTPLTe3zTs5zTa1zTp2zTp3zTp4zTp5zTp7zTp8zTp9ztGAM` — so it is chunked by fixed width,
    /// not by any separator. Trailing NULs and any partial trailing chunk are discarded.
    static func parse(sensorProperty: String) -> [String] {
        let characters = Array(sensorProperty.unicodeScalars.filter { $0 != "\0" })
        guard characters.count >= keyLength else {
            return []
        }

        var keys: [String] = []
        var index = 0
        while index + keyLength <= characters.count {
            let scalars = characters[index ..< (index + keyLength)]
            index += keyLength

            // A real key is printable ASCII; anything else means the blob is not what we think.
            guard scalars.allSatisfy({ $0.isASCII && $0.value > 0x20 }) else {
                continue
            }
            keys.append(String(String.UnicodeScalarView(scalars)))
        }
        return keys
    }

    /// Maps a sensor key to the component it measures, or nil for sensors this app does not
    /// surface (battery `TB*`, Wi-Fi `TW*`, ambient/skin `Ta*`/`Ts*`, and the non-temperature
    /// entries such as `mTPL` that share the same property blob).
    static func component(for key: String) -> TemperatureComponent? {
        guard key.count == keyLength else {
            return nil
        }

        // Apple Silicon publishes the GPU as `tGAM`; Intel uses the `TG` family.
        if key == "tGAM" || key.hasPrefix("TG") {
            return .gpu
        }

        // Apple Silicon CPU clusters: `Tp*` performance cores, `Te*` efficiency cores.
        // Intel CPU dies and proximity sensors: `TC*`.
        if key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("TC") {
            return .cpu
        }

        return nil
    }

    /// Decodes an SMC value using the type tag the SMC itself reports for that key.
    /// Apple Silicon sensors are `flt ` (little-endian `Float32`); older Intel SMCs use the
    /// `sp78` signed 8.8 fixed-point encoding.
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count == 4 else {
                return nil
            }
            let bitPattern = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bitPattern))
            return value.isFinite ? value : nil
        case "sp78":
            guard bytes.count == 2 else {
                return nil
            }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        default:
            return nil
        }
    }

    static func isPlausible(_ celsius: Double) -> Bool {
        celsius.isFinite && plausibleRange.contains(celsius)
    }

    /// The hottest plausible reading, which is what the Temperature card reports — a single
    /// cool core says nothing useful while a neighbouring one is throttling.
    static func hottest(of readings: [Double]) -> Double? {
        readings.filter(isPlausible).max()
    }

    /// Used when a Mac does not publish a `smctempsensor0` sensor list. Covers the common
    /// Apple Silicon and Intel CPU/GPU keys; unreadable ones are dropped during probing, so
    /// listing a key that does not exist on this machine costs nothing at runtime.
    static let fallbackKeys: [String] = [
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0b", "Tp0f", "Tp0j", "Tp0n",
        "Tp2z", "Tp3z", "Tp4z", "Tp5z", "Tp7z", "Tp8z", "Tp9z",
        "Te05", "Te0S", "Te3z",
        "TC0P", "TC0D", "TC0E", "TC0F", "TCAD",
        "tGAM", "TG0D", "TG0P",
    ]
}

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

    /// Rewrites a discovered sensor key to the variant holding the *live* reading.
    ///
    /// Each sensor exists in four variants — `Tp3a`, `Tp3b`, `Tp3x`, `Tp3z` — and the
    /// `smctempsensor0` node advertises the `z` one. That is not the current temperature.
    /// Measured on 2026-08-08 across a load spike and cool-down: `Tp3z` is *always* exactly
    /// `Tp3x + 12.00` and `Tp3b` *always* exactly `Tp3a + 7.40`, so `b` and `z` are derived
    /// offset registers; `x`/`z` are additionally noisy and do not track load. Only `a` tracks
    /// load smoothly and agrees with an independent reader — `Te3a` read 35.93 against Stats'
    /// 35.9 for the same sensor, while the `z` variant this originally shipped with reported
    /// 81.2 °C against a true 41.0 °C.
    static func instantaneousKey(for key: String) -> String {
        guard key.count == keyLength, let suffix = key.last, "bxz".contains(suffix) else {
            return key
        }
        return String(key.dropLast()) + "a"
    }

    /// Maps a sensor key to the component it measures, or nil for sensors this app does not
    /// surface (battery `TB*`, Wi-Fi `TW*`, ambient/skin `Ta*`/`Ts*`, and the non-temperature
    /// entries such as `mTPL` that share the same property blob).
    static func component(for key: String) -> TemperatureComponent? {
        guard key.count == keyLength else {
            return nil
        }

        // Intel exposes real fractional GPU die sensors as the `TG` family. Apple Silicon has
        // no validated equivalent: `tGAM` looks like one and is the key most correlated with
        // GPU load, but it reports whole numbers only (49, 50, 51, … 86) where every genuine
        // sensor here reports fractions, so it is a margin/limit register rather than a
        // temperature. Reporting nothing beats reporting a number that cannot be corroborated.
        if key.hasPrefix("TG") {
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
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp2a", "Tp3a", "Tp4a", "Tp5a", "Tp7a", "Tp8a", "Tp9a",
        "Te0a", "Te3a", "Te05", "Te0S",
        "TC0P", "TC0D", "TC0E", "TC0F", "TCAD",
        "TG0D", "TG0P",
    ]
}

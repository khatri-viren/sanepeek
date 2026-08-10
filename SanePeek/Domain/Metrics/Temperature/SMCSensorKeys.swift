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

    struct SensorDefinition: Equatable, Sendable {
        let key: String
        let component: TemperatureComponent
    }

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
    /// offset registers; `x`/`z` are additionally noisy and do not track load. Only the
    /// catalog's canonical live suffix tracks load smoothly: lowercase `a` for `Tp`/`Te`, and
    /// uppercase `A` for the catalogued `Tf` family. This agrees with an independent reader —
    /// `Te3a` read 35.93 against Stats' 35.9 for the same sensor, while the `z` variant this
    /// originally shipped with reported 81.2 °C against a true 41.0 °C.
    static func instantaneousKey(for key: String) -> String {
        // Some generations use a non-standard suffix as the actual live key (for example,
        // M1/M2 publish `Tp0b`). Preserve exact catalog entries before deriving family variants.
        if knownSensorComponents[key] != nil {
            return key
        }

        guard (key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("Tf")),
              key.count == keyLength,
              let suffix = key.last,
              "bxz".contains(suffix)
        else {
            return key
        }

        let stem = String(key.dropLast())
        let lowercaseVariant = stem + "a"
        if knownSensorComponents[lowercaseVariant] != nil {
            return lowercaseVariant
        }

        // M3's Tf catalog uses an uppercase A for the live variant, unlike the lowercase
        // Tp/Te families. Preserve the catalog's casing so component lookup still succeeds.
        let uppercaseVariant = stem + "A"
        if knownSensorComponents[uppercaseVariant] != nil {
            return uppercaseVariant
        }

        // Keep the historical fallback for an unknown family; it will be rejected by the
        // component catalog rather than silently inventing a supported sensor.
        return lowercaseVariant
    }

    /// Maps a sensor key to the component it measures, or nil for sensors this app does not
    /// surface (battery `TB*`, Wi-Fi `TW*`, ambient/skin `Ta*`/`Ts*`, and the non-temperature
    /// entries such as `mTPL` that share the same property blob).
    static func component(for key: String) -> TemperatureComponent? {
        guard key.count == keyLength else {
            return nil
        }

        if let knownComponent = knownSensorComponents[key] {
            return knownComponent
        }

        // Intel exposes real fractional GPU die sensors as the `TG` family. Apple Silicon
        // families are intentionally not inferred from prefixes: M3 uses `Tf*` for both CPU
        // and GPU sensors, while M2/M4/M5 GPU keys use lowercase `Tg*`. Those are mapped in the
        // explicit catalog below.
        if key.hasPrefix("TG") {
            return .gpu
        }

        // Apple Silicon CPU clusters and Intel CPU dies/proximity sensors. Unknown Apple
        // Silicon GPU-shaped keys remain unclassified until validated and added to the catalog.
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

    /// Observed CPU/GPU temperature keys across Apple Silicon generations. Exact SMC names are
    /// undocumented and the same key can occur on multiple families, so this is a union of
    /// candidates rather than a model switch. Every candidate is still validated by SMC key
    /// info, supported encoding, and a plausible reading before it becomes a sensor.
    static let knownSensors: [SensorDefinition] = [
        // M1/M2/M4 CPU cluster keys.
        SensorDefinition(key: "Tp01", component: .cpu),
        SensorDefinition(key: "Tp05", component: .cpu),
        SensorDefinition(key: "Tp09", component: .cpu),
        SensorDefinition(key: "Tp0D", component: .cpu),
        SensorDefinition(key: "Tp0X", component: .cpu),
        SensorDefinition(key: "Tp0b", component: .cpu),
        SensorDefinition(key: "Tp0f", component: .cpu),
        SensorDefinition(key: "Tp0j", component: .cpu),
        SensorDefinition(key: "Tp1h", component: .cpu),
        SensorDefinition(key: "Tp1t", component: .cpu),
        SensorDefinition(key: "Tp1p", component: .cpu),
        SensorDefinition(key: "Tp1l", component: .cpu),
        SensorDefinition(key: "Tp0H", component: .cpu),
        SensorDefinition(key: "Tp0L", component: .cpu),
        SensorDefinition(key: "Tp0P", component: .cpu),
        SensorDefinition(key: "Tp0T", component: .cpu),
        SensorDefinition(key: "Tp2a", component: .cpu),
        SensorDefinition(key: "Tp3a", component: .cpu),
        SensorDefinition(key: "Tp4a", component: .cpu),
        SensorDefinition(key: "Tp5a", component: .cpu),
        SensorDefinition(key: "Tp7a", component: .cpu),
        SensorDefinition(key: "Tp8a", component: .cpu),
        SensorDefinition(key: "Tp9a", component: .cpu),

        // M1/M3/M4 efficiency cluster keys.
        SensorDefinition(key: "Te3a", component: .cpu),
        SensorDefinition(key: "Te04", component: .cpu),
        SensorDefinition(key: "Te05", component: .cpu),
        SensorDefinition(key: "Te06", component: .cpu),
        SensorDefinition(key: "Te0L", component: .cpu),
        SensorDefinition(key: "Te0P", component: .cpu),
        SensorDefinition(key: "Te0S", component: .cpu),
        SensorDefinition(key: "Te09", component: .cpu),
        SensorDefinition(key: "Te0H", component: .cpu),

        // M3 uses Tf* for both CPU and GPU, so these keys must be explicit.
        SensorDefinition(key: "Tf04", component: .cpu),
        SensorDefinition(key: "Tf09", component: .cpu),
        SensorDefinition(key: "Tf0A", component: .cpu),
        SensorDefinition(key: "Tf0B", component: .cpu),
        SensorDefinition(key: "Tf0D", component: .cpu),
        SensorDefinition(key: "Tf0E", component: .cpu),
        SensorDefinition(key: "Tf44", component: .cpu),
        SensorDefinition(key: "Tf49", component: .cpu),
        SensorDefinition(key: "Tf4A", component: .cpu),
        SensorDefinition(key: "Tf4B", component: .cpu),
        SensorDefinition(key: "Tf4D", component: .cpu),
        SensorDefinition(key: "Tf4E", component: .cpu),
        SensorDefinition(key: "Tf14", component: .gpu),
        SensorDefinition(key: "Tf18", component: .gpu),
        SensorDefinition(key: "Tf19", component: .gpu),
        SensorDefinition(key: "Tf1A", component: .gpu),
        SensorDefinition(key: "Tf24", component: .gpu),
        SensorDefinition(key: "Tf28", component: .gpu),
        SensorDefinition(key: "Tf29", component: .gpu),
        SensorDefinition(key: "Tf2A", component: .gpu),

        // M4/M5 CPU cluster keys.
        SensorDefinition(key: "Tp0V", component: .cpu),
        SensorDefinition(key: "Tp0Y", component: .cpu),
        SensorDefinition(key: "Tp0e", component: .cpu),
        SensorDefinition(key: "Tp00", component: .cpu),
        SensorDefinition(key: "Tp04", component: .cpu),
        SensorDefinition(key: "Tp08", component: .cpu),
        SensorDefinition(key: "Tp0C", component: .cpu),
        SensorDefinition(key: "Tp0G", component: .cpu),
        SensorDefinition(key: "Tp0K", component: .cpu),
        SensorDefinition(key: "Tp0O", component: .cpu),
        SensorDefinition(key: "Tp0R", component: .cpu),
        SensorDefinition(key: "Tp0U", component: .cpu),
        SensorDefinition(key: "Tp0a", component: .cpu),
        SensorDefinition(key: "Tp0d", component: .cpu),
        SensorDefinition(key: "Tp0g", component: .cpu),
        SensorDefinition(key: "Tp0m", component: .cpu),
        SensorDefinition(key: "Tp0p", component: .cpu),
        SensorDefinition(key: "Tp0u", component: .cpu),
        SensorDefinition(key: "Tp0y", component: .cpu),

        // M1/M2/M4/M5 GPU keys. Lowercase `Tg*` is intentional.
        SensorDefinition(key: "Tg05", component: .gpu),
        SensorDefinition(key: "Tg0D", component: .gpu),
        SensorDefinition(key: "Tg0L", component: .gpu),
        SensorDefinition(key: "Tg0T", component: .gpu),
        SensorDefinition(key: "Tg0f", component: .gpu),
        SensorDefinition(key: "Tg0j", component: .gpu),
        SensorDefinition(key: "Tg0G", component: .gpu),
        SensorDefinition(key: "Tg0H", component: .gpu),
        SensorDefinition(key: "Tg1U", component: .gpu),
        SensorDefinition(key: "Tg1k", component: .gpu),
        SensorDefinition(key: "Tg0K", component: .gpu),
        SensorDefinition(key: "Tg0d", component: .gpu),
        SensorDefinition(key: "Tg0e", component: .gpu),
        SensorDefinition(key: "Tg0k", component: .gpu),
        SensorDefinition(key: "Tg0U", component: .gpu),
        SensorDefinition(key: "Tg0X", component: .gpu),
        SensorDefinition(key: "Tg0g", component: .gpu),
        SensorDefinition(key: "Tg1Y", component: .gpu),
        SensorDefinition(key: "Tg1c", component: .gpu),
        SensorDefinition(key: "Tg1g", component: .gpu),

        // Independently validated aggregate die/hotspot keys used as safe candidates.
        SensorDefinition(key: "TCMz", component: .cpu),
        SensorDefinition(key: "TCMb", component: .cpu),
        SensorDefinition(key: "TCHP", component: .cpu),
        SensorDefinition(key: "TRDX", component: .gpu),
    ]

    private static let knownSensorComponents = Dictionary(
        uniqueKeysWithValues: knownSensors.map { ($0.key, $0.component) }
    )

    /// Used when a Mac does not publish a usable `smctempsensor0` sensor list. Unreadable
    /// candidates are dropped during probing, so listing a key that does not exist on this
    /// machine costs only a bounded set of initialization calls.
    static let fallbackKeys: [String] = knownSensors.map(\.key) + [
        // Intel CPU/GPU keys.
        "TC0P", "TC0D", "TC0E", "TC0F", "TCAD",
        "TG0D", "TG0P",
    ]

    /// A non-empty registry property can contain only non-temperature entries such as `mTPL`.
    /// Treat discovery as authoritative only when it contains at least one key this reader can
    /// classify; otherwise probe the union catalog. Returned discovered keys are normalized to
    /// their live-reading variants, so callers do not need to repeat this transformation.
    static func candidates(from discovered: [String]) -> [String] {
        let normalized = discovered.map(instantaneousKey(for:))
        let hasUsableTemperatureKey = normalized
            .contains { component(for: $0) != nil }
        return hasUsableTemperatureKey ? normalized : fallbackKeys
    }
}

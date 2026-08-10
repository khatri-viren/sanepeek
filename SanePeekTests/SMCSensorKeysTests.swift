import Foundation
import Testing

@testable import SanePeek

/// Covers the decoding and classification the SMC path depends on, without touching IOKit.
///
/// The values here are not invented: the sensor blob, the key names, and the readings are what
/// the machine this was developed on actually reported (MacBookAir10,1 / M1) when probed on
/// 2026-08-08. The hardware half — that `IOServiceOpen("AppleSMC")` succeeds unsandboxed and
/// fails with `kIOReturnNotPermitted` under the App Sandbox — cannot be asserted here, since a
/// test bundle inherits whatever the host app's entitlements are.
@Suite("SMC sensor keys")
struct SMCSensorKeysTests {
    /// Verbatim from this Mac's `smctempsensor0` IORegistry node.
    private static let m1SensorBlob = "mTPLTe3zTs5zTa1zTp2zTp3zTp4zTp5zTp7zTp8zTp9ztGAM"

    @Test("Splits the run-together sensor blob into four-character keys")
    func parsesSensorBlob() {
        let keys = SMCSensorKeys.parse(sensorProperty: Self.m1SensorBlob)

        #expect(keys.count == 12)
        #expect(keys.first == "mTPL")
        #expect(keys.last == "tGAM")
        #expect(keys.contains("Tp3z"))
        #expect(keys.allSatisfy { $0.count == 4 })
    }

    @Test("Trailing NULs and partial chunks are discarded rather than yielding junk keys")
    func parseIgnoresPaddingAndRemainder() {
        #expect(SMCSensorKeys.parse(sensorProperty: "Tp2z\0\0\0\0") == ["Tp2z"])
        #expect(SMCSensorKeys.parse(sensorProperty: "Tp2ztGA") == ["Tp2z"])
        #expect(SMCSensorKeys.parse(sensorProperty: "") == [])
        #expect(SMCSensorKeys.parse(sensorProperty: "Tp2") == [])
    }

    @Test("Falls back when the registry lists only non-temperature entries")
    func mTPLDoesNotSuppressFallback() {
        #expect(SMCSensorKeys.candidates(from: ["mTPL"]) == SMCSensorKeys.fallbackKeys)
    }

    @Test("Classifies the real keys this Mac publishes, once rewritten to live variants")
    func classifiesDiscoveredKeys() {
        let keys = SMCSensorKeys.candidates(from: SMCSensorKeys.parse(sensorProperty: Self.m1SensorBlob))
        let cpu = keys.filter { SMCSensorKeys.component(for: $0) == .cpu }
        let gpu = keys.filter { SMCSensorKeys.component(for: $0) == .gpu }

        // Seven Tp* sensors plus the Te3 efficiency-core one.
        #expect(cpu.count == 8)
        #expect(cpu.allSatisfy { $0.hasSuffix("a") })
        // `tGAM` is deliberately not treated as a GPU sensor — it reports whole numbers only,
        // so it is a margin register rather than a die temperature.
        #expect(gpu.isEmpty)
    }

    @Test("The advertised z/b/x variants are rewritten to the live a variant")
    func rewritesToInstantaneousVariant() {
        #expect(SMCSensorKeys.instantaneousKey(for: "Tp3z") == "Tp3a")
        #expect(SMCSensorKeys.instantaneousKey(for: "Tp3x") == "Tp3a")
        #expect(SMCSensorKeys.instantaneousKey(for: "Tp3b") == "Tp3a")
        // Already live, or not part of the suffixed family — left alone.
        #expect(SMCSensorKeys.instantaneousKey(for: "Tp3a") == "Tp3a")
        #expect(SMCSensorKeys.instantaneousKey(for: "Tf0z") == "Tf0A")
        #expect(SMCSensorKeys.instantaneousKey(for: "Tf1x") == "Tf1A")
        #expect(SMCSensorKeys.instantaneousKey(for: "Tf2b") == "Tf2A")
        #expect(SMCSensorKeys.instantaneousKey(for: "TC0P") == "TC0P")
        #expect(SMCSensorKeys.instantaneousKey(for: "TCMz") == "TCMz")
        #expect(SMCSensorKeys.instantaneousKey(for: "TG0D") == "TG0D")
        #expect(SMCSensorKeys.instantaneousKey(for: "Tp3") == "Tp3")
    }

    @Test("Normalizes discovered M3 Tf variants to catalog keys")
    func normalizesM3TfVariants() {
        let candidates = SMCSensorKeys.candidates(from: ["Tf0z", "Tf1x", "Tf2b"])

        #expect(candidates == ["Tf0A", "Tf1A", "Tf2A"])
        #expect(candidates.allSatisfy { SMCSensorKeys.component(for: $0) != nil })
    }

    @Test("Classifies representative M2 through M5 sensor families")
    func classifiesAppleSiliconFamilies() {
        let expected: [(String, TemperatureComponent)] = [
            ("Tp1h", .cpu), ("Tg0f", .gpu), // M2
            ("Te05", .cpu), ("Tf04", .cpu), ("Tf14", .gpu), // M3
            ("Te0H", .cpu), ("Tp0V", .cpu), ("Tg0G", .gpu), // M4
            ("Tp00", .cpu), ("Tp0O", .cpu), ("Tg0U", .gpu), // M5
        ]

        for (key, component) in expected {
            #expect(SMCSensorKeys.component(for: key) == component, "\(key) classification")
        }
    }

    @Test("Non-temperature and non-die sensors are excluded, not misfiled as CPU")
    func excludesUnrelatedSensors() {
        // `mTPL` is a power limit and `tGAM` an integer-valued margin register, not
        // temperatures; the rest are real sensors this app deliberately does not surface.
        for key in ["mTPL", "tGAM", "Ts5a", "Ta1a", "TB0T", "TW0P"] {
            #expect(SMCSensorKeys.component(for: key) == nil, "\(key) should be unclassified")
        }
    }

    @Test("Covers the Intel key families as well as Apple Silicon")
    func classifiesIntelKeys() {
        #expect(SMCSensorKeys.component(for: "TC0P") == .cpu)
        #expect(SMCSensorKeys.component(for: "TC0D") == .cpu)
        #expect(SMCSensorKeys.component(for: "TG0D") == .gpu)
        #expect(SMCSensorKeys.component(for: "TG0P") == .gpu)
    }

    @Test("Rejects keys that are not four characters")
    func rejectsMalformedKeys() {
        #expect(SMCSensorKeys.component(for: "Tp") == nil)
        #expect(SMCSensorKeys.component(for: "Tp2zz") == nil)
        #expect(SMCSensorKeys.component(for: "") == nil)
    }

    @Test("Decodes the little-endian flt encoding Apple Silicon sensors use")
    func decodesFloatEncoding() {
        // 79.03 C as reported by Tp3z, encoded little-endian.
        let bitPattern = Float(79.03).bitPattern
        let bytes = (0 ..< 4).map { UInt8((bitPattern >> (8 * UInt32($0))) & 0xFF) }

        let decoded = try! #require(SMCSensorKeys.decode(bytes, type: "flt "))
        #expect(abs(decoded - 79.03) < 0.01)
    }

    @Test("Decodes the sp78 fixed-point encoding older Intel SMCs use")
    func decodesFixedPointEncoding() {
        // sp78 is signed 8.8: 0x4B40 is 75.25 C.
        let decoded = try! #require(SMCSensorKeys.decode([0x4B, 0x40], type: "sp78"))
        #expect(abs(decoded - 75.25) < 0.001)
    }

    @Test("Refuses encodings and payload sizes it does not understand")
    func rejectsUnknownEncodings() {
        #expect(SMCSensorKeys.decode([0x00, 0x00, 0x00, 0x00], type: "ui32") == nil)
        #expect(SMCSensorKeys.decode([0x00, 0x00], type: "flt ") == nil)
        #expect(SMCSensorKeys.decode([0x00, 0x00, 0x00, 0x00], type: "sp78") == nil)
    }

    @Test("Treats unpopulated and impossible readings as misreads")
    func filtersImplausibleReadings() {
        #expect(!SMCSensorKeys.isPlausible(0))
        #expect(!SMCSensorKeys.isPlausible(-40))
        #expect(!SMCSensorKeys.isPlausible(3000))
        #expect(!SMCSensorKeys.isPlausible(.nan))
        #expect(!SMCSensorKeys.isPlausible(.infinity))
        #expect(SMCSensorKeys.isPlausible(79.03))
    }

    @Test("Reports the hottest core, since a cool neighbour hides throttling")
    func reportsHottestReading() {
        let cores = [72.27, 79.03, 76.78, 66.88, 74.19, 75.73, 76.45]
        #expect(SMCSensorKeys.hottest(of: cores) == 79.03)
    }

    @Test("Implausible readings cannot become the reported maximum")
    func hottestIgnoresImplausibleReadings() {
        #expect(SMCSensorKeys.hottest(of: [72.27, 3000, 79.03]) == 79.03)
        #expect(SMCSensorKeys.hottest(of: [0, 0]) == nil)
        #expect(SMCSensorKeys.hottest(of: []) == nil)
    }

    @Test("Every fallback key is one the classifier actually recognises")
    func fallbackKeysAreAllClassifiable() {
        for key in SMCSensorKeys.fallbackKeys {
            #expect(SMCSensorKeys.component(for: key) != nil, "\(key) is unclassified")
        }
    }
}

/// Exercises the real IOKit path against whatever sensors this machine has.
///
/// Everything else in this file runs on stubs, which cannot catch a wrong `SMCKeyData` layout,
/// a bad selector, or a byte-order slip — the failures most likely to occur here. This suite
/// can only assert conditionally: it skips when no sensors are readable, which is the correct
/// outcome on an unknown Mac *and* on a sandboxed build, and those two are indistinguishable
/// from inside the process.
@Suite("SMC hardware read")
struct SMCTemperatureAdapterHardwareTests {
    @Test("Readings from real sensors are plausible die temperatures")
    func readsPlausibleTemperatures() {
        let adapter = SMCTemperatureAdapter()
        guard adapter.isSupported else {
            return
        }

        guard case let .available(sample) = adapter.read(at: .zero) else {
            Issue.record("adapter reported sensors but returned no reading")
            return
        }

        #expect(sample.cpuCelsius != nil || sample.gpuCelsius != nil)
        for value in [sample.cpuCelsius, sample.gpuCelsius].compactMap({ $0 }) {
            // A running Mac's die sits well above room temperature; anything under 10 C means
            // the bytes were misread rather than that the machine is cold.
            #expect(value > 10 && value < 120, "implausible reading \(value) C")
        }
    }

    @Test("Consecutive reads stay stable, so the connection survives reuse")
    func repeatedReadsRemainStable() {
        let adapter = SMCTemperatureAdapter()
        guard adapter.isSupported else {
            return
        }

        let readings: [Double] = (0 ..< 5).compactMap { _ in
            guard case let .available(sample) = adapter.read(at: .zero) else {
                return nil
            }
            return sample.cpuCelsius
        }

        #expect(readings.count == 5, "a reuse of the open connection failed")
        // Die temperature cannot swing 40 C across a handful of back-to-back reads; that would
        // mean the payload is being decoded inconsistently rather than that the Mac heated up.
        if let low = readings.min(), let high = readings.max() {
            #expect(high - low < 40, "readings ranged \(low)...\(high) C")
        }
    }
}

/// Covers `LiveTemperatureReader`'s handling of whatever the adapter hands back, using a stub
/// so the outcomes that are hard to provoke on real hardware (a sandboxed refusal, a sensor
/// returning garbage) are still exercised.
@Suite("LiveTemperatureReader")
struct LiveTemperatureReaderTests {
    private struct StubAdapter: TemperatureSystemAdapter {
        let isSupported: Bool
        let result: MetricResult<TemperatureSystemSample>

        func read(at timestamp: MetricTimestamp) -> MetricResult<TemperatureSystemSample> {
            result
        }
    }

    private static let timestamp = MetricTimestamp.zero

    @Test("Reports unsupported when the adapter has no readable sensors")
    func unsupportedWhenAdapterHasNoSensors() async {
        let reader = LiveTemperatureReader(
            adapter: StubAdapter(isSupported: false, result: .unavailable(.unsupported))
        )

        guard case .unavailable(.unsupported) = await reader.read(at: Self.timestamp) else {
            Issue.record("expected unsupported")
            return
        }
    }

    @Test("Passes real readings through to the snapshot")
    func publishesReadings() async {
        let reader = LiveTemperatureReader(
            adapter: StubAdapter(
                isSupported: true,
                result: .available(TemperatureSystemSample(cpuCelsius: 79.03, gpuCelsius: 54.0))
            )
        )

        guard case let .available(snapshot) = await reader.read(at: Self.timestamp) else {
            Issue.record("expected a reading")
            return
        }
        #expect(snapshot.cpuCelsius == 79.03)
        #expect(snapshot.gpuCelsius == 54.0)
    }

    @Test("A GPU-only Mac still reports, rather than being treated as unsupported")
    func publishesPartialReadings() async {
        let reader = LiveTemperatureReader(
            adapter: StubAdapter(
                isSupported: true,
                result: .available(TemperatureSystemSample(cpuCelsius: nil, gpuCelsius: 54.0))
            )
        )

        guard case let .available(snapshot) = await reader.read(at: Self.timestamp) else {
            Issue.record("expected a reading")
            return
        }
        #expect(snapshot.cpuCelsius == nil)
        #expect(snapshot.gpuCelsius == 54.0)
    }

    @Test("An implausible reading is reported as invalid rather than shown to the user")
    func rejectsImplausibleReadings() async {
        let reader = LiveTemperatureReader(
            adapter: StubAdapter(
                isSupported: true,
                result: .available(TemperatureSystemSample(cpuCelsius: 3000, gpuCelsius: nil))
            )
        )

        guard case let .failed(failure) = await reader.read(at: Self.timestamp) else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.kind == .invalidData)
    }

    @Test("Every sensor going quiet reports no data instead of a bogus zero")
    func reportsNoDataWhenAllSensorsAreSilent() async {
        let reader = LiveTemperatureReader(
            adapter: StubAdapter(
                isSupported: true,
                result: .available(TemperatureSystemSample(cpuCelsius: nil, gpuCelsius: nil))
            )
        )

        guard case .unavailable(.noData) = await reader.read(at: Self.timestamp) else {
            Issue.record("expected noData")
            return
        }
    }
}

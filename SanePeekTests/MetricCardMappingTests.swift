import Foundation
import Testing

@testable import SanePeek

@Suite("MetricCardMapping")
struct MetricCardMappingTests {
    private static let timestamp = MetricTimestamp.zero

    @Test("CPU card renders utilization, core breakdown, and threshold status")
    func cpuCardMapsAvailableSnapshot() {
        let snapshot = CPUSnapshot(
            timestamp: Self.timestamp,
            utilization: 0.5,
            logicalCoreCount: 10,
            performanceCoreCount: 6,
            efficiencyCoreCount: 4
        )

        let card = MetricCardMapping.cpuCard(snapshot, history: [0.1, 0.5])

        #expect(card.primaryValue == "50%")
        #expect(card.secondaryValue == "6P + 4E cores")
        #expect(card.status == .normal)
        #expect(card.unavailableMessage == nil)
        #expect(card.sparklineValues == [0.1, 0.5])
    }

    @Test("CPU card status escalates at the documented warning and critical fractions")
    func cpuCardStatusThresholds() {
        let warning = MetricCardMapping.cpuCard(
            CPUSnapshot(timestamp: Self.timestamp, utilization: 0.80),
            history: []
        )
        let critical = MetricCardMapping.cpuCard(
            CPUSnapshot(timestamp: Self.timestamp, utilization: 0.95),
            history: []
        )

        #expect(warning.status == .warning)
        #expect(critical.status == .critical)
    }

    @Test("CPU card falls back to the unavailable presentation when the snapshot is missing or unavailable")
    func cpuCardHandlesUnavailability() {
        let nilCard = MetricCardMapping.cpuCard(nil, history: [])
        let unavailableCard = MetricCardMapping.cpuCard(
            .unavailable(at: Self.timestamp, reason: .temporarilyUnavailable),
            history: []
        )

        for card in [nilCard, unavailableCard] {
            #expect(card.primaryValue == "--")
            #expect(card.status == nil)
            #expect(card.sparklineValues.isEmpty)
        }

        #expect(nilCard.unavailableMessage == MetricUnavailableReason.noData.userMessage)
        #expect(unavailableCard.unavailableMessage == "This metric is temporarily unavailable.")
    }

    @Test("Memory card status mirrors the OS-provided pressure state directly")
    func memoryCardUsesPressureForStatus() {
        let normal = MetricCardMapping.memoryCard(
            MemorySnapshot(timestamp: Self.timestamp, usedBytes: 1, availableBytes: 1, pressure: .normal),
            history: []
        )
        let critical = MetricCardMapping.memoryCard(
            MemorySnapshot(timestamp: Self.timestamp, usedBytes: 1, availableBytes: 1, pressure: .critical),
            history: []
        )

        #expect(normal.status == .normal)
        #expect(critical.status == .critical)
    }

    @Test("Storage card computes usage fraction and hides the sparkline in favor of the usage ring")
    func storageCardComputesUsageFraction() {
        let card = MetricCardMapping.storageCard(
            StorageSnapshot(
                timestamp: Self.timestamp,
                usedBytes: 500_000_000_000,
                availableBytes: 500_000_000_000,
                totalBytes: 1_000_000_000_000
            )
        )

        #expect(card.usageFraction == 0.5)
        #expect(card.sparklineValues.isEmpty)
        #expect(card.status == .normal)
    }

    @Test("Storage card byte formatting respects the injected unit system consistently")
    func storageCardRespectsByteUnitSystem() {
        let snapshot = StorageSnapshot(
            timestamp: Self.timestamp,
            usedBytes: 1_073_741_824,
            availableBytes: 1_073_741_824,
            totalBytes: 2_147_483_648
        )

        let decimal = MetricCardMapping.storageCard(snapshot, formatter: MetricFormatter(byteUnitSystem: .decimal))
        let binary = MetricCardMapping.storageCard(snapshot, formatter: MetricFormatter(byteUnitSystem: .binary))

        #expect(decimal.primaryValue.hasSuffix("GB"))
        #expect(binary.primaryValue.hasSuffix("GiB"))
        #expect(decimal.usageFraction == binary.usageFraction)
    }

    @Test("Network card reports download as primary and upload as secondary, with no status")
    func networkCardMapsThroughput() {
        let card = MetricCardMapping.networkCard(
            NetworkSnapshot(
                timestamp: Self.timestamp,
                downloadBytesPerSecond: 1_000_000,
                uploadBytesPerSecond: 500_000,
                connectivity: .connected,
                interfaceNames: ["en0"]
            ),
            history: [1, 2, 3]
        )

        #expect(card.primaryValue == "1 MB/s")
        #expect(card.secondaryValue == "\u{2191} 500 kB/s")
        #expect(card.status == nil)
        #expect(card.sparklineValues == [1, 2, 3])
    }

    @Test("Battery card status only evaluates thresholds while unplugged")
    func batteryCardStatusIgnoresLowChargeWhilePlugged() {
        let chargingLow = MetricCardMapping.batteryCard(
            BatterySnapshot(timestamp: Self.timestamp, percentage: 0.05, chargingState: .charging)
        )
        let unpluggedLow = MetricCardMapping.batteryCard(
            BatterySnapshot(timestamp: Self.timestamp, percentage: 0.05, chargingState: .unplugged)
        )

        #expect(chargingLow.status == .normal)
        #expect(unpluggedLow.status == .critical)
    }

    @Test("GPU card is hidden for a nil snapshot, an unavailable snapshot, and a nil utilization")
    func gpuCardHidesWhenUnreliable() {
        let nilSnapshot = MetricCardMapping.gpuCard(nil, history: [])
        let unavailableSnapshot = MetricCardMapping.gpuCard(
            .unavailable(at: Self.timestamp, reason: .unsupported),
            history: []
        )
        let nilUtilization = MetricCardMapping.gpuCard(
            GPUSnapshot(timestamp: Self.timestamp, utilization: nil, name: "Some GPU"),
            history: []
        )

        #expect(nilSnapshot == nil)
        #expect(unavailableSnapshot == nil)
        #expect(nilUtilization == nil)
    }

    @Test("GPU card renders when utilization is reliably available")
    func gpuCardShowsWhenAvailable() {
        let card = MetricCardMapping.gpuCard(
            GPUSnapshot(timestamp: Self.timestamp, utilization: 0.3, name: "Some GPU"),
            history: [0.1, 0.3]
        )

        #expect(card?.primaryValue == "30%")
        #expect(card?.secondaryValue == "Some GPU")
    }
}

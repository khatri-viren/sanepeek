import Foundation
import Testing

@testable import SanePeek

@Suite("PopoverChartAxis")
struct PopoverChartAxisTests {
    @Test("Tick values are plain quarters of max, not rounded to nice numbers")
    func tickValuesAreQuartersOfMax() {
        #expect(PopoverChartAxis.tickValues(max: 75) == [18.75, 37.5, 56.25, 75])
    }

    @Test("Tick values fall back to a single zero tick for a non-positive or non-finite max")
    func tickValuesFallBackForDegenerateMax() {
        #expect(PopoverChartAxis.tickValues(max: 0) == [0])
        #expect(PopoverChartAxis.tickValues(max: -5) == [0])
        #expect(PopoverChartAxis.tickValues(max: .nan) == [0])
    }

    @Test("Labels use each metric's real unit")
    func labelsUseRealUnitPerMetric() {
        let formatter = MetricFormatter()

        #expect(PopoverChartAxis.label(for: 0.5, kind: .cpu, formatter: formatter) == "50%")
        #expect(PopoverChartAxis.label(for: 0.25, kind: .gpu, formatter: formatter) == "25%")
        #expect(PopoverChartAxis.label(for: 2_000_000_000, kind: .memory, formatter: formatter) == formatter.bytes(UInt64(2_000_000_000)))
        #expect(PopoverChartAxis.label(for: 45.2, kind: .temperature, formatter: formatter) == formatter.temperature(45.2))
        #expect(PopoverChartAxis.label(for: 332_000, kind: .network, formatter: formatter) == "\(formatter.bytes(UInt64(332_000)))/s")
    }

    @Test("Labels guard against non-finite values instead of trapping on the UInt64 conversion")
    func labelsGuardNonFiniteValues() {
        let formatter = MetricFormatter()

        #expect(PopoverChartAxis.label(for: .nan, kind: .memory, formatter: formatter) == "--")
        #expect(PopoverChartAxis.label(for: .infinity, kind: .network, formatter: formatter) == "--")
    }

    @Test("Sparkline scale follows a narrow temperature range instead of zero")
    func sparklineScaleFollowsNarrowTemperatureRange() {
        let domain = SparklineScale.domain(for: [54, 56, 62])

        #expect(domain.lowerBound > 45)
        #expect(domain.upperBound < 70)
        #expect(domain.contains(54))
        #expect(domain.contains(62))
    }

    @Test("Sparkline scale gives constant data breathing room and guards invalid history")
    func sparklineScaleHandlesDegenerateHistory() {
        let constant = SparklineScale.domain(for: [60, 60, 60])

        #expect(constant.lowerBound < 60)
        #expect(constant.upperBound > 60)

        let invalid = SparklineScale.domain(for: [.nan, .infinity, -.infinity])
        #expect(invalid.lowerBound == 0)
        #expect(invalid.upperBound == 1)
    }

    @Test("Sparkline history is right-anchored on the fixed chart window")
    func sparklineHistoryIsRightAnchored() {
        let display = SparklineLayout.displayData(for: [10, 20, 30], windowSize: 60)

        #expect(display.values == [10, 20, 30])
        #expect(display.offset == 57)
        #expect(display.offset + display.values.count - 1 == 59)
        #expect(display.xUpperBound == 59)
    }

    @Test("Sparkline layout keeps only the newest finite samples")
    func sparklineLayoutCapsAndFiltersHistory() {
        let display = SparklineLayout.displayData(
            for: [1, .nan, 2, .infinity, 3, 4],
            windowSize: 3
        )

        #expect(display.values == [2, 3, 4])
        #expect(display.offset == 0)
        #expect(display.xUpperBound == 2)
    }
}

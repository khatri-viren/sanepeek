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
}

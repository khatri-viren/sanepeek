import Foundation

/// Axis tick positions and labels for `PopoverMetricChartView`'s chart, kept as a pure
/// enum (like `MetricCardMapping`/`MetricFormatter`) so unit selection per `MetricKind` is
/// testable without standing up a view.
nonisolated enum PopoverChartAxis {
    /// Evenly spaced ticks across `0...max` (e.g. `max: 75` -> `[18.75, 37.5, 56.25, 75]`) —
    /// deliberately plain quarter-of-max positions, not Swift Charts' automatic "nice round
    /// number" placement, to match the reference design's axis.
    static func tickValues(max: Double, count: Int = 4) -> [Double] {
        guard max.isFinite, max > 0, count > 0 else { return [0] }
        return (1...count).map { max * Double($0) / Double(count) }
    }

    /// Formats one chart value using the metric's real unit: `sparklineValues` is a fraction
    /// for cpu/gpu, raw bytes for memory, Celsius for temperature, and bytes/sec for network
    /// (see `MetricCardMapping`/`LiveDashboardTickFeed` for where each history array comes
    /// from) — storage/battery never reach here since their `sparklineValues` is always empty.
    static func label(for value: Double, kind: MetricKind, formatter: MetricFormatter) -> String {
        // Converting to `UInt64` below traps on NaN/infinite, so guard the same way
        // `MetricFormatter`'s own Double-taking formatters do.
        guard value.isFinite else { return "--" }
        let nonNegative = max(0, value)
        switch kind {
        case .cpu, .gpu:
            return formatter.percentage(nonNegative)
        case .memory:
            return formatter.bytes(UInt64(nonNegative))
        case .temperature:
            return formatter.temperature(nonNegative)
        case .network:
            return "\(formatter.bytes(UInt64(nonNegative)))/s"
        case .storage, .battery:
            return formatter.percentage(nonNegative)
        }
    }
}

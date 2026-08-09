import Charts
import SwiftUI

/// One colored series in a history chart.
nonisolated struct MetricChartSeries: Identifiable, Equatable {
    /// Doubles as the `ForEach` identity and the chart's series label.
    let id: String
    let color: Color
    let values: [Double]

    init(_ id: String, color: Color, values: [Double]) {
        self.id = id
        self.color = color
        self.values = values
    }
}

/// The bar-chart shape shared by the CPU and Memory hero cards and the menu bar popup:
/// one bar per tick, with each series stacked on the last, optionally topped up to the
/// domain's ceiling by a `remainderColor` band (CPU's "Idle", Memory's "Free") so every
/// bar reads as a whole rather than stopping short at the sum of its parts.
///
/// Stacking is implicit: same-`x` `BarMark`s with a plain `y:` value stack cumulatively in
/// declaration order, which is exactly what the user -> system -> idle ordering relies on.
struct StackedHistoryChart: View {
    let series: [MetricChartSeries]
    /// Fills each bar from the stacked total up to `domain.upperBound`; nil leaves the
    /// remainder empty (correct when the series don't sum to a meaningful whole).
    var remainderColor: Color?
    var domain: ClosedRange<Double> = 0...1
    /// Gridline positions. Labels are drawn on the leading edge only when `axisLabel` is
    /// set — the dashboard's hero cards pass nil for gridlines alone, while the popup
    /// labels them, since its charts have no legend column beside them to give scale.
    var axisValues: [Double] = [0, 0.5, 1.0]
    var axisLabel: ((Double) -> String)?

    var body: some View {
        // Right-anchor to the "now" edge: before the window fills up, leave the
        // unpopulated seconds blank on the left instead of stretching a handful of
        // samples across the full width.
        let trimmed = series.map { Array($0.values.suffix(MetricChartLayout.historyWindowSize)) }
        let sampleCount = trimmed.map(\.count).max() ?? 0
        let offset = MetricChartLayout.historyWindowSize - sampleCount

        GeometryReader { proxy in
            let slotWidth = proxy.size.width / CGFloat(MetricChartLayout.historyWindowSize)
            let barWidth = max(MetricChartLayout.minimumBarWidth, slotWidth * MetricChartLayout.barWidthFraction)

            Chart {
                ForEach(0..<sampleCount, id: \.self) { index in
                    ForEach(Array(series.enumerated()), id: \.element.id) { seriesIndex, entry in
                        BarMark(
                            x: .value("Tick", offset + index),
                            y: .value(entry.id, value(in: trimmed[seriesIndex], at: index)),
                            width: .fixed(barWidth)
                        )
                        .foregroundStyle(entry.color)
                        .cornerRadius(MetricChartLayout.barCornerRadius)
                    }

                    if let remainderColor {
                        let stacked = trimmed.reduce(0.0) { $0 + value(in: $1, at: index) }
                        BarMark(
                            x: .value("Tick", offset + index),
                            y: .value("Remainder", max(0, domain.upperBound - stacked)),
                            width: .fixed(barWidth)
                        )
                        .foregroundStyle(remainderColor)
                        .cornerRadius(MetricChartLayout.barCornerRadius)
                    }
                }
            }
            .chartXScale(domain: 0...(MetricChartLayout.historyWindowSize - 1))
            .chartXAxis(.hidden)
            .chartYScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: axisValues) { axisValue in
                    AxisGridLine()
                    if let axisLabel, let raw = axisValue.as(Double.self) {
                        AxisValueLabel {
                            Text(axisLabel(raw))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .transaction { transaction in
                // The popup animates the chart panel when the selected metric changes. Keep
                // Swift Charts from also interpolating all 60 bars inside that transition,
                // which makes CPU/Memory swaps flash or briefly stack the old and new series.
                // This chart redraws every tick, so mark-level animation is not useful here
                // either.
                transaction.animation = nil
            }
        }
    }

    private func value(in values: [Double], at index: Int) -> Double {
        index < values.count ? values[index] : 0
    }
}

/// The Network card's chart shape: two series mirrored from a shared zero baseline
/// (download up, upload down), shared between the dashboard's hero card and the popup.
struct BidirectionalHistoryChart: View {
    let upSeries: MetricChartSeries
    let downSeries: MetricChartSeries
    /// Half-height of the symmetric domain (`-magnitude...magnitude`).
    let magnitude: Double
    var axisLabel: ((Double) -> String)?

    var body: some View {
        // Each direction is right-anchored independently: unlike a stacked chart, the two
        // series are never combined per index, so they can fill in at their own pace.
        let up = Array(upSeries.values.suffix(MetricChartLayout.historyWindowSize))
        let down = Array(downSeries.values.suffix(MetricChartLayout.historyWindowSize))
        let upOffset = MetricChartLayout.historyWindowSize - up.count
        let downOffset = MetricChartLayout.historyWindowSize - down.count

        GeometryReader { proxy in
            let slotWidth = proxy.size.width / CGFloat(MetricChartLayout.historyWindowSize)
            let barWidth = max(MetricChartLayout.minimumBarWidth, slotWidth * MetricChartLayout.mirroredBarWidthFraction)

            Chart {
                ForEach(Array(up.enumerated()), id: \.offset) { index, value in
                    // Explicit yStart/yEnd, not a plain `y:` value: same-x BarMarks using
                    // the single-value form stack cumulatively (see StackedHistoryChart),
                    // which would put the upload bar on top of the download bar instead of
                    // mirroring both from a shared zero baseline.
                    BarMark(
                        x: .value("Tick", upOffset + index),
                        yStart: .value("Baseline", 0),
                        yEnd: .value(upSeries.id, value),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(upSeries.color)
                    .cornerRadius(MetricChartLayout.barCornerRadius)
                }
                ForEach(Array(down.enumerated()), id: \.offset) { index, value in
                    BarMark(
                        x: .value("Tick", downOffset + index),
                        yStart: .value("Baseline", 0),
                        yEnd: .value(downSeries.id, -value),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(downSeries.color)
                    .cornerRadius(MetricChartLayout.barCornerRadius)
                }
            }
            .chartXScale(domain: 0...(MetricChartLayout.historyWindowSize - 1))
            .chartXAxis(.hidden)
            .chartYScale(domain: -magnitude...magnitude)
            .chartYAxis {
                // Only the peak and the baseline get labels: the domain is symmetric, so
                // marking -magnitude too would print the same text twice (once per
                // direction) and collide with the time axis printed under the chart. The
                // legend already says which direction is which.
                AxisMarks(position: .leading, values: axisLabel == nil ? [0] : [0, magnitude]) { axisValue in
                    AxisGridLine()
                    if let axisLabel, let raw = axisValue.as(Double.self) {
                        AxisValueLabel {
                            Text(axisLabel(abs(raw)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .transaction { transaction in
                // As with the stacked chart, the panel owns selection motion; the mirrored
                // bars should redraw as one stable snapshot instead of animating underneath it.
                transaction.animation = nil
            }
        }
    }
}

/// The "60s ... now" scale printed under every history chart.
struct HistoryChartTimeAxis: View {
    var body: some View {
        HStack {
            Text("60s")
            Spacer()
            Text("45s")
            Spacer()
            Text("30s")
            Spacer()
            Text("15s")
            Spacer()
            Text("now")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

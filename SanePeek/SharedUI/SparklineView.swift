import Charts
import SwiftUI

nonisolated struct SparklineDisplayData: Equatable {
    let values: [Double]
    let offset: Int
    let xUpperBound: Int
}

nonisolated enum SparklineLayout {
    static func displayData(for values: [Double], windowSize: Int) -> SparklineDisplayData {
        let safeWindowSize = max(windowSize, 1)
        let finiteValues = values.filter { $0.isFinite }
        let displayValues = Array(finiteValues.suffix(safeWindowSize))

        return SparklineDisplayData(
            values: displayValues,
            offset: safeWindowSize - displayValues.count,
            xUpperBound: max(safeWindowSize - 1, 1)
        )
    }
}

/// Chooses a readable y-domain for a sparkline without pinning a positive metric to zero.
/// Temperature history is usually a narrow band (for example, 54...62°C), so a zero-based
/// domain makes a meaningful change look flat at the top of the chart.
nonisolated enum SparklineScale {
    static func domain(for values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter { $0.isFinite }
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return 0...1
        }

        let midpoint = (minimum + maximum) / 2
        let observedSpan = maximum - minimum
        let minimumSpan = max(abs(midpoint) * 0.08, 0.1)
        let visibleSpan = max(observedSpan, minimumSpan)
        let padding = max(visibleSpan * 0.2, minimumSpan * 0.25)

        var lowerBound = midpoint - visibleSpan / 2 - padding
        let upperBound = midpoint + visibleSpan / 2 + padding
        if minimum >= 0 {
            lowerBound = max(0, lowerBound)
        }

        return lowerBound...upperBound
    }
}

/// Renders up to 60 samples as an adaptive trend line on a fixed, right-anchored timeline.
struct SparklineView: View {
    let values: [Double]
    let color: Color
    /// When supplied, the sparkline gets the same leading gridlines and value labels as the
    /// popup's CPU and Memory charts. Compact sparklines leave this nil to stay compact.
    let axisLabel: ((Double) -> String)?

    init(values: [Double], color: Color, axisLabel: ((Double) -> String)? = nil) {
        self.values = values
        self.color = color
        self.axisLabel = axisLabel
    }

    var body: some View {
        let displayData = SparklineLayout.displayData(
            for: values,
            windowSize: MetricChartLayout.historyWindowSize
        )
        let domain = SparklineScale.domain(for: displayData.values)

        Chart {
            ForEach(Array(displayData.values.enumerated()), id: \.offset) { index, value in
                let slot = displayData.offset + index

                // The wash is anchored to the chart's lower bound rather than an implicit
                // zero baseline, so it remains a subtle context cue instead of swallowing
                // the popup with a large block of color.
                AreaMark(
                    x: .value("Sample", slot),
                    yStart: .value("Baseline", domain.lowerBound),
                    yEnd: .value("Value", value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Sample", slot),
                    y: .value("Value", value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(color)
            }

            if let latest = displayData.values.last {
                PointMark(
                    x: .value("Sample", displayData.offset + displayData.values.count - 1),
                    y: .value("Value", latest)
                )
                .foregroundStyle(color)
                .symbolSize(28)
            }
        }
        // Keep the plot on the same 60-slot timeline as the bar charts. New samples enter at
        // the right edge and older samples shift one slot to the left instead of expanding or
        // re-centering the whole history while the window is filling.
        .chartXScale(domain: 0...displayData.xUpperBound)
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis {
            if let axisLabel {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { axisValue in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = axisValue.as(Double.self) {
                            Text(axisLabel(raw))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .transaction { transaction in
            // This is a live sliding window. Animating marks by their array index makes every
            // historical point morph once per tick, which looks like the whole line is changing
            // instead of the newest sample arriving at the right and pushing history left.
            transaction.animation = nil
        }
    }
}

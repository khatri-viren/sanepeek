import Charts
import SwiftUI

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

/// Renders up to 60 samples as an adaptive trend line. Caller is responsible for capping
/// the sample count; this view just draws whatever it's given.
struct SparklineView: View {
    let values: [Double]
    let color: Color
    /// When supplied, the sparkline gets the same leading gridlines and value labels as the
    /// popup's CPU and Memory charts. Dashboard sparklines leave this nil to stay compact.
    let axisLabel: ((Double) -> String)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(values: [Double], color: Color, axisLabel: ((Double) -> String)? = nil) {
        self.values = values
        self.color = color
        self.axisLabel = axisLabel
    }

    var body: some View {
        let displayValues = values.filter { $0.isFinite }
        let domain = SparklineScale.domain(for: displayValues)
        let xUpperBound = max(displayValues.count - 1, 1)

        Chart {
            ForEach(Array(displayValues.enumerated()), id: \.offset) { index, value in
                // The wash is anchored to the chart's lower bound rather than an implicit
                // zero baseline, so it remains a subtle context cue instead of swallowing
                // the popup with a large block of color.
                AreaMark(
                    x: .value("Sample", index),
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
                    x: .value("Sample", index),
                    y: .value("Value", value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(color)
            }

            if let latest = displayValues.last {
                PointMark(
                    x: .value("Sample", displayValues.count - 1),
                    y: .value("Value", latest)
                )
                .foregroundStyle(color)
                .symbolSize(28)
            }
        }
        .chartXScale(domain: 0...xUpperBound)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: values)
    }
}

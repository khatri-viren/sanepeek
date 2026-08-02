import Charts
import SwiftUI

/// Renders up to 60 samples as a filled line. Caller is responsible for capping
/// the sample count; this view just draws whatever it's given.
struct SparklineView: View {
    let values: [Double]
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Sample", index),
                    y: .value("Value", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)

                AreaMark(
                    x: .value("Sample", index),
                    y: .value("Value", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color.opacity(0.15))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: values)
    }
}

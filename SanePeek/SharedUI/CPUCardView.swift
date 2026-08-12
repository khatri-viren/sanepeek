import Charts
import SwiftUI

/// Hero CPU card: big utilization number, a user/system/idle legend, and a
/// stacked history chart. Distinct from `MetricCardView` because this shape
/// (legend + stacked chart side by side) doesn't fit the shared
/// icon/primary/secondary/trailing template the other five cards use.
struct CPUCardView: View {
    let model: MetricCardModel
    let detail: CPUCardDetail?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: MetricSpacing.cardSpacing) {
            header

            if let message = model.unavailableMessage {
                Text(message)
                    .font(MetricTypography.secondaryMetric)
                    .foregroundStyle(.secondary)
            } else {
                body(for: detail)
            }
        }
        .metricCardBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
        .accessibilityIdentifier("metrics.card.\(model.id.rawValue)")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.accentColor)
                    .frame(width: 8, height: 8)

                Text("Processor")
                    .font(.headline)

                if let chipName = detail?.chipName {
                    Text("\u{00B7} \(chipName)")
                        .font(MetricTypography.secondaryMetric)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if model.unavailableMessage == nil {
                // `MetricCardStatus.tintColor` is nil for `.normal`, so the pill
                // stays neutral at steady load and only tints for warning/critical
                // — color is additive to the word here, never the only signal.
                let tint = model.status?.tintColor
                Text(statusWord(model.status))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint ?? .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((tint ?? .secondary).opacity(tint == nil ? 0.15 : 0.2), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func body(for detail: CPUCardDetail?) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.primaryValue)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: model.primaryValue)

                VStack(alignment: .leading, spacing: 10) {
                    legendRow(color: model.accentColor, label: "User", value: detail?.userPercentageText ?? "--")
                    legendRow(color: MetricPalette.cpuSystem, label: "System", value: detail?.systemPercentageText ?? "--")
                    legendRow(color: MetricPalette.idleFill, label: "Idle", value: detail?.idlePercentageText ?? "--")
                }
            }
            // Fixed, not just a minimum: a `Spacer` inside `legendRow` otherwise
            // reads as infinitely flexible to the outer HStack, which then splits
            // width evenly between this column and the chart instead of giving
            // the chart everything past this column's actual content.
            .frame(width: 170, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                CPUCardView.chart(for: detail, accentColor: model.accentColor)
                    .frame(minHeight: 120)

                HistoryChartTimeAxis()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func legendRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(MetricTypography.secondaryMetric)
            Spacer(minLength: 12)
            Text(value)
                .font(MetricTypography.secondaryMetric.weight(.semibold))
        }
    }

    /// The user/system stack, shared with the menu bar popup so both render CPU history
    /// identically. `axisLabel` is nil here — the legend column beside the chart already
    /// gives the scale, so the compact chart shows gridlines alone.
    ///
    /// `showsIdle` fills the rest of each bar up to 100%, matching the "Idle" legend swatch,
    /// so the bar's full height reads as the whole sample rather than stopping short. The
    /// popup turns it off: at its smaller size the idle band crowded the actual load.
    static func chart(
        for detail: CPUCardDetail?,
        accentColor: Color,
        axisLabel: ((Double) -> String)? = nil,
        showsIdle: Bool = true
    ) -> some View {
        StackedHistoryChart(
            series: [
                MetricChartSeries("User", color: accentColor, values: detail?.userHistory ?? []),
                MetricChartSeries("System", color: MetricPalette.cpuSystem, values: detail?.systemHistory ?? [])
            ],
            remainderColor: showsIdle ? MetricPalette.idleFill : nil,
            axisLabel: axisLabel
        )
    }

    private func statusWord(_ status: MetricCardStatus?) -> String {
        switch status {
        case .none, .normal:
            "STEADY"
        case .warning:
            "ELEVATED"
        case .critical:
            "HIGH"
        }
    }
}

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
        .accessibilityIdentifier("dashboard.card.\(model.id.rawValue)")
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
                stackedChart(for: detail)
                    .frame(minHeight: 120)

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

    private func stackedChart(for detail: CPUCardDetail?) -> some View {
        let userHistory = Array((detail?.userHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        let systemHistory = Array((detail?.systemHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        // Before the window fills up, anchor samples to the right (now) edge
        // and leave the unpopulated seconds as blank space on the left, rather
        // than stretching a handful of samples across the full chart width.
        let offset = MetricChartLayout.historyWindowSize - userHistory.count

        return GeometryReader { proxy in
            let slotWidth = proxy.size.width / CGFloat(MetricChartLayout.historyWindowSize)
            let barWidth = max(MetricChartLayout.minimumBarWidth, slotWidth * MetricChartLayout.barWidthFraction)

            Chart {
                ForEach(Array(userHistory.enumerated()), id: \.offset) { index, user in
                    let system = index < systemHistory.count ? systemHistory[index] : 0
                    let idle = max(0, 1 - user - system)
                    let x = offset + index

                    BarMark(x: .value("Tick", x), y: .value("User", user), width: .fixed(barWidth))
                        .foregroundStyle(model.accentColor)
                        .cornerRadius(2)

                    BarMark(x: .value("Tick", x), y: .value("System", system), width: .fixed(barWidth))
                        .foregroundStyle(MetricPalette.cpuSystem)
                        .cornerRadius(2)

                    // Fills the rest of the bar up to 100%, matching the "Idle"
                    // legend swatch, so the bar's full height always reads as the
                    // whole sample rather than stopping short at user + system.
                    BarMark(x: .value("Tick", x), y: .value("Idle", idle), width: .fixed(barWidth))
                        .foregroundStyle(MetricPalette.idleFill)
                        .cornerRadius(2)
                }
            }
            .chartXScale(domain: 0...(MetricChartLayout.historyWindowSize - 1))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1.0]) {
                    AxisGridLine()
                }
            }
            .chartYScale(domain: 0...1)
            .chartLegend(.hidden)
            // No implicit animation here: this redraws every tick, and animating
            // a full 60-bar replace made old and new bars cross-fade on top of
            // each other, reading as bars piling up instead of a clean sliding
            // window.
        }
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

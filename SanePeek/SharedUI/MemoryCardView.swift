import Charts
import SwiftUI

/// Hero Memory card: big utilization number, an App/Wired/Compressed/Free
/// legend, and a stacked history chart. Mirrors `CPUCardView`'s shape —
/// distinct from `MetricCardView` for the same reason CPU is: the legend +
/// stacked chart layout doesn't fit the shared icon/primary/secondary/trailing
/// template the other cards use.
struct MemoryCardView: View {
    let model: MetricCardModel
    let detail: MemoryCardDetail?

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

                Text("Memory")
                    .font(.headline)

                if let totalRAMText = detail?.totalRAMText {
                    Text("\u{00B7} \(totalRAMText)")
                        .font(MetricTypography.secondaryMetric)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if model.unavailableMessage == nil {
                // `MetricCardStatus.tintColor` is nil for `.normal`, so the pill
                // stays neutral at steady pressure and only tints for warning/critical
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
    private func body(for detail: MemoryCardDetail?) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.primaryValue)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: model.primaryValue)

                VStack(alignment: .leading, spacing: 10) {
                    legendRow(color: model.accentColor, label: "App", value: detail?.appPercentageText ?? "--")
                    legendRow(color: MetricPalette.memoryWired, label: "Wired", value: detail?.wiredPercentageText ?? "--")
                    legendRow(color: MetricPalette.memoryCompressed, label: "Compressed", value: detail?.compressedPercentageText ?? "--")
                    legendRow(color: MetricPalette.idleFill, label: "Free", value: detail?.freePercentageText ?? "--")
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

    private func stackedChart(for detail: MemoryCardDetail?) -> some View {
        let appHistory = Array((detail?.appHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        let wiredHistory = Array((detail?.wiredHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        let compressedHistory = Array((detail?.compressedHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        // Before the window fills up, anchor samples to the right (now) edge
        // and leave the unpopulated seconds as blank space on the left, rather
        // than stretching a handful of samples across the full chart width.
        let offset = MetricChartLayout.historyWindowSize - appHistory.count

        return GeometryReader { proxy in
            let slotWidth = proxy.size.width / CGFloat(MetricChartLayout.historyWindowSize)
            let barWidth = max(MetricChartLayout.minimumBarWidth, slotWidth * MetricChartLayout.barWidthFraction)

            Chart {
                ForEach(Array(appHistory.enumerated()), id: \.offset) { index, app in
                    let wired = index < wiredHistory.count ? wiredHistory[index] : 0
                    let compressed = index < compressedHistory.count ? compressedHistory[index] : 0
                    let free = max(0, 1 - app - wired - compressed)
                    let x = offset + index

                    BarMark(x: .value("Tick", x), y: .value("App", app), width: .fixed(barWidth))
                        .foregroundStyle(model.accentColor)
                        .cornerRadius(2)

                    BarMark(x: .value("Tick", x), y: .value("Wired", wired), width: .fixed(barWidth))
                        .foregroundStyle(MetricPalette.memoryWired)
                        .cornerRadius(2)

                    BarMark(x: .value("Tick", x), y: .value("Compressed", compressed), width: .fixed(barWidth))
                        .foregroundStyle(MetricPalette.memoryCompressed)
                        .cornerRadius(2)

                    // Fills the rest of the bar up to 100%, matching the "Free"
                    // legend swatch, so the bar's full height always reads as the
                    // whole sample rather than stopping short at app + wired + compressed.
                    BarMark(x: .value("Tick", x), y: .value("Free", free), width: .fixed(barWidth))
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

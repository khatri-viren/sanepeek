import Charts
import SwiftUI

/// Hero Network card: Download/Upload value columns and a bidirectional history
/// chart (download bars up, upload bars down, mirrored from a zero baseline).
/// No status pill in the header — network has no threshold policy (`status`
/// is always nil), unlike `CPUCardView`/`TemperatureCardView`'s header.
struct NetworkCardView: View {
    let model: MetricCardModel
    let detail: NetworkCardDetail?

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

                Text("Network")
                    .font(.headline)
            }

            Spacer()

            if model.unavailableMessage == nil, let subtitle = detail?.subtitleText {
                Text(subtitle)
                    .font(MetricTypography.secondaryMetric)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func body(for detail: NetworkCardDetail?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 32) {
                valueColumn(icon: "arrowtriangle.down.fill", label: "Download", color: model.accentColor, value: detail?.downloadText ?? "--")
                valueColumn(icon: "arrowtriangle.up.fill", label: "Upload", color: MetricPalette.networkUpload, value: detail?.uploadText ?? "--")
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                NetworkCardView.chart(for: detail, accentColor: model.accentColor)
                    .frame(minHeight: 100)

                HistoryChartTimeAxis()
            }
        }
    }

    private func valueColumn(icon: String, label: String, color: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(label)
                    .font(MetricTypography.secondaryMetric)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: value)
        }
    }

    /// The mirrored download/upload chart, shared with the menu bar popup so both render
    /// network history identically. `axisLabel` is nil here — the Download/Upload value
    /// columns above the chart already give the scale, so the dashboard shows the zero
    /// baseline alone.
    static func chart(for detail: NetworkCardDetail?, accentColor: Color, axisLabel: ((Double) -> String)? = nil) -> some View {
        let downloadHistory = Array((detail?.downloadHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        let uploadHistory = Array((detail?.uploadHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        // Computed over the full visible window, not just the latest tick: a spike
        // inflates the axis and decays naturally as it ages out of the window, with no
        // extra smoothing state needed. The idle floor keeps this from collapsing to a
        // degenerate 0...0 domain when both directions are quiet.
        let magnitude = max(
            downloadHistory.max() ?? 0,
            uploadHistory.max() ?? 0,
            MetricChartLayout.networkIdleFloorBytesPerSecond
        )

        // The opacity applies to the bars only — the header dot, the Download/Upload
        // column icons, and the popup's legend swatches all stay solid, since at their
        // size the effect would read as washed out rather than lighter.
        return BidirectionalHistoryChart(
            upSeries: MetricChartSeries(
                "Download",
                color: accentColor.opacity(MetricPalette.networkSeriesOpacity),
                values: downloadHistory
            ),
            downSeries: MetricChartSeries(
                "Upload",
                color: MetricPalette.networkUpload.opacity(MetricPalette.networkSeriesOpacity),
                values: uploadHistory
            ),
            magnitude: magnitude,
            axisLabel: axisLabel
        )
    }
}

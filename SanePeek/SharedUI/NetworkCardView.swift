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
                bidirectionalChart(for: detail)
                    .frame(minHeight: 100)

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

    private func bidirectionalChart(for detail: NetworkCardDetail?) -> some View {
        let downloadHistory = Array((detail?.downloadHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        let uploadHistory = Array((detail?.uploadHistory ?? []).suffix(MetricChartLayout.historyWindowSize))
        // Right-anchor each series independently: download and upload don't
        // need to be zipped per index (unlike CPU's user/system/idle stack),
        // so they can fill in at their own pace if their history lengths differ.
        let downloadOffset = MetricChartLayout.historyWindowSize - downloadHistory.count
        let uploadOffset = MetricChartLayout.historyWindowSize - uploadHistory.count
        // Computed over the full visible window, not just the latest tick: a
        // spike inflates the axis and decays naturally as it ages out of the
        // window, with no extra smoothing state needed. The idle floor keeps
        // this from collapsing to a degenerate 0...0 domain when both are quiet.
        let magnitude = max(
            downloadHistory.max() ?? 0,
            uploadHistory.max() ?? 0,
            MetricChartLayout.networkIdleFloorBytesPerSecond
        )

        return GeometryReader { proxy in
            let slotWidth = proxy.size.width / CGFloat(MetricChartLayout.historyWindowSize)
            let barWidth = max(MetricChartLayout.minimumBarWidth, slotWidth * MetricChartLayout.barWidthFraction)

            Chart {
                ForEach(Array(downloadHistory.enumerated()), id: \.offset) { index, download in
                    // Explicit yStart/yEnd, not a plain `y:` value: same-x BarMarks
                    // using the single-value form stack cumulatively in declaration
                    // order (see CPUCardView.stackedChart's user->system->idle
                    // chain), which would put the upload bar on top of the download
                    // bar instead of mirroring both from a shared zero baseline.
                    BarMark(
                        x: .value("Tick", downloadOffset + index),
                        yStart: .value("Baseline", 0),
                        yEnd: .value("Download", download),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(model.accentColor)
                    .cornerRadius(2)
                }
                ForEach(Array(uploadHistory.enumerated()), id: \.offset) { index, upload in
                    BarMark(
                        x: .value("Tick", uploadOffset + index),
                        yStart: .value("Baseline", 0),
                        yEnd: .value("Upload", -upload),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(MetricPalette.networkUpload)
                    .cornerRadius(2)
                }
            }
            .chartXScale(domain: 0...(MetricChartLayout.historyWindowSize - 1))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0]) {
                    AxisGridLine()
                }
            }
            .chartYScale(domain: -magnitude...magnitude)
            .chartLegend(.hidden)
            // No implicit animation: redrawing all 60 bars every tick with an
            // animation cross-fades old and new bars on top of each other,
            // reading as bars piling up instead of a clean sliding window
            // (same reasoning as CPUCardView.stackedChart).
        }
    }
}

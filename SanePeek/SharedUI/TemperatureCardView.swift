import Charts
import SwiftUI

/// Hero Temperature card: a needle gauge for the hottest CPU/GPU reading, a CPU/GPU
/// legend, and a history sparkline. Mirrors `CPUCardView`/`MemoryCardView`'s shape, but
/// swaps the big hero number + stacked breakdown chart for a gauge + plain trend line,
/// since there's one trending value here ("hottest"), not a breakdown that sums to a
/// whole.
struct TemperatureCardView: View {
    let model: MetricCardModel
    let detail: TemperatureCardDetail?

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

                Text("Temperature")
                    .font(.headline)
            }

            Spacer()

            if model.unavailableMessage == nil {
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
    private func body(for detail: TemperatureCardDetail?) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                TemperatureGaugeView(celsius: detail?.hottestCelsius, valueText: detail?.hottestText ?? "--")

                VStack(alignment: .leading, spacing: 10) {
                    legendRow(label: "CPU", value: detail?.cpuText ?? "--")
                    legendRow(label: "GPU", value: detail?.gpuText ?? "--")
                }
            }
            .frame(width: 170, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                SparklineView(
                    values: Array(model.sparklineValues.suffix(MetricChartLayout.historyWindowSize)),
                    color: model.accentColor
                )
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

    /// Plain label+value row, no colored swatch — unlike CPU/Memory's legend rows,
    /// there's no stacked total here to visually decompose.
    private func legendRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(MetricTypography.secondaryMetric)
            Spacer(minLength: 12)
            Text(value)
                .font(MetricTypography.secondaryMetric.weight(.semibold))
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

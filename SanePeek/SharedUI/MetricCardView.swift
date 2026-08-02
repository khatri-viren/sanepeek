import SwiftUI

/// Reusable card shell: icon, title, primary/secondary value, optional status,
/// unavailable state, and a trailing slot for whatever visual a metric needs
/// (sparkline, usage ring, or nothing).
struct MetricCardView<Trailing: View>: View {
    let model: MetricCardModel
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: MetricSpacing.headerSpacing) {
            HStack {
                Label(model.title, systemImage: model.systemImage)
                    .font(MetricTypography.label)
                    .foregroundStyle(model.accentColor)

                Spacer()

                if let status = model.status,
                   let symbolName = status.symbolName,
                   let tint = status.tintColor,
                   let word = status.accessibilityWord {
                    Label(word, systemImage: symbolName)
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }

            if let message = model.unavailableMessage {
                Spacer(minLength: 4)
                Text(message)
                    .font(MetricTypography.secondaryMetric)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.primaryValue)
                            .font(MetricTypography.primaryMetric)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .default, value: model.primaryValue)

                        if let secondary = model.secondaryValue {
                            Text(secondary)
                                .font(MetricTypography.secondaryMetric)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    trailing()
                        .frame(height: 44)
                }
            }
        }
        .metricCardBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
    }
}

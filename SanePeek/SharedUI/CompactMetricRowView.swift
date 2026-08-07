import SwiftUI

/// A single metric row for the menu bar popup's compact glance list: icon, title, and value —
/// no chart, unlike the dashboard's hero/generic cards, which are too large for a popup.
struct CompactMetricRowView: View {
    let model: MetricCardModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.systemImage)
                .foregroundStyle(model.accentColor)
                .frame(width: 18)

            Text(model.title)
                .font(.subheadline)

            Spacer()

            if let symbolName = model.status?.symbolName, let tint = model.status?.tintColor {
                Image(systemName: symbolName)
                    .font(.caption2)
                    .foregroundStyle(tint)
            }

            Text(model.unavailableMessage == nil ? model.primaryValue : "--")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.status?.tintColor ?? .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
    }
}

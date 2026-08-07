import SwiftUI

/// A single metric row for the menu bar popup's compact glance list: icon, title, and value —
/// no chart, unlike the dashboard's hero/generic cards, which are too large for a popup.
///
/// Doubles as a tab in the popup's side-by-side layout: `MenuBarPopoverView` wraps this in a
/// `Button` and passes `isSelected` so the row currently driving `PopoverMetricChartView`
/// reads as the active tab, the same "selection = tinted background" language macOS sidebars use.
struct CompactMetricRowView: View {
    let model: MetricCardModel
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.systemImage)
                .foregroundStyle(model.accentColor)
                .frame(width: 18)

            Text(model.title)
                .font(isSelected ? .subheadline.weight(.semibold) : .subheadline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            if let symbolName = model.status?.symbolName, let tint = model.status?.tintColor {
                Image(systemName: symbolName)
                    .font(.caption2)
                    .foregroundStyle(tint)
            }

            Text(model.unavailableMessage == nil ? model.primaryValue : "--")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.status?.tintColor ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            model.accentColor.opacity(isSelected ? 0.12 : 0),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
    }
}

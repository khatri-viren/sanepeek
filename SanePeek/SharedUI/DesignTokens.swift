import SwiftUI

nonisolated enum MetricSpacing {
    static let cardPadding: CGFloat = 20
    static let cardSpacing: CGFloat = 16
    static let headerSpacing: CGFloat = 6
    static let gridSpacing: CGFloat = 16
}

nonisolated enum MetricCornerRadius {
    static let card: CGFloat = 20
}

/// `primaryMetric` stays a fixed size — it's the hero digit display and the card
/// grid is sized around it, so letting it scale with Dynamic Type would break
/// layout. `secondaryMetric`/`label` are ordinary text and scale with the
/// system text size, bounded by the `.dynamicTypeSize` clamp applied at the
/// dashboard/settings roots.
nonisolated enum MetricTypography {
    static let primaryMetric = Font.system(size: 52, weight: .semibold, design: .rounded)
    static let secondaryMetric = Font.system(.subheadline, design: .rounded).weight(.medium)
    static let label = Font.system(.caption, design: .rounded).weight(.medium)
}

/// Colors match the PRD's metric palette table. GPU has no assigned color in the
/// PRD; teal is an inferred accent kept visually distinct from the other five.
nonisolated enum MetricPalette {
    static let cpu = Color.blue
    static let memory = Color.purple
    static let storage = Color.gray
    static let network = Color.cyan
    static let battery = Color.green
    static let gpu = Color.teal
    static let warning = Color.orange
    static let critical = Color.red
}

private struct MetricCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(MetricSpacing.cardPadding)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: MetricCornerRadius.card, style: .continuous)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

extension View {
    func metricCardBackground() -> some View {
        modifier(MetricCardBackground())
    }
}

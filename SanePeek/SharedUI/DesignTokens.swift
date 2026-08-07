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
    /// Second tone in the CPU card's user/system breakdown; a shade of `cpu`
    /// rather than a new hue, so the pair still reads as one metric.
    static let cpuSystem = Color.blue.opacity(0.5)
    static let memory = Color.blue
    /// Wired/Compressed tones in the Memory card's App/Wired/Compressed breakdown;
    /// shades of `memory` rather than new hues, matching the `cpu`/`cpuSystem` pattern.
    static let memoryWired = Color.blue.opacity(0.6)
    static let memoryCompressed = Color.blue.opacity(0.35)
    static let storage = Color.gray
    static let network = Color.cyan
    /// Network's upload-direction data color. Shares `warning`'s hue but is a
    /// distinct token, not a reuse: `warning` is load-bearing status-pill
    /// semantics (CPU/storage/battery/temperature all tint their pill orange
    /// for "warning"), while this is a plain data-series color — network has
    /// no threshold policy and never shows a status pill.
    static let networkUpload = Color.orange
    static let battery = Color.green
    static let gpu = Color.teal
    /// Temperature has no assigned color in the PRD either; pink is the only
    /// remaining unclaimed system hue distinct from every other metric and from
    /// the orange/red reserved for warning/critical.
    static let temperature = Color.pink
    static let warning = Color.orange
    static let critical = Color.red

    /// Gauge-only "normal" zone color; distinct from `battery` even though both are
    /// green, since this represents the pressure scale's face, not a metric identity.
    static let pressureNormal = Color.green

    /// Shared "unfilled" swatch/bar fill for a breakdown's remainder (CPU's Idle,
    /// Memory's Free). `Color.secondary.opacity(0.3)` nearly disappeared against the
    /// card's dark material background; this is deliberately more opaque.
    static let idleFill = Color.secondary.opacity(0.1)
}

/// Tuning for the stacked-history charts shared by the CPU and Memory hero cards.
nonisolated enum MetricChartLayout {
    /// Matches the ring buffer capacity `MetricsEngine`/`FixtureDashboardTickFeed`
    /// retain history in, and the "60s...now" axis labels below each chart.
    static let historyWindowSize = 60

    /// Fraction of each bar's slot the bar itself occupies — the remainder is
    /// always a gap, whether the slot is wide (big window) or narrow (small
    /// window), instead of a fixed point value that either wastes space on a
    /// big card or disappears on a small one.
    static let barWidthFraction: CGFloat = 0.7
    static let minimumBarWidth: CGFloat = 2

    /// Floor for the Network card's bidirectional chart y-domain so it never
    /// collapses to a degenerate 0...0 range when both download and upload are idle.
    static let networkIdleFloorBytesPerSecond: Double = 1_024
}

private struct MetricCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(MetricSpacing.cardPadding)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: MetricCornerRadius.card, style: .continuous)
            )
    }
}

extension View {
    func metricCardBackground() -> some View {
        modifier(MetricCardBackground())
    }
}

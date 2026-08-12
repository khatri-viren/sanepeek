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
/// settings root.
nonisolated enum MetricTypography {
    static let primaryMetric = Font.system(size: 52, weight: .semibold, design: .rounded)
    static let secondaryMetric = Font.system(.subheadline, design: .rounded).weight(.medium)
    static let label = Font.system(.caption, design: .rounded).weight(.medium)
}

/// Mostly the PRD's metric palette table, with three deliberate divergences the
/// PRD records: Memory and Network are blue rather than purple/cyan, and GPU and
/// Temperature have no PRD entry at all (teal and pink are inferred accents kept
/// distinct from the other metrics and from the warning/critical orange-red).
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
    /// Deliberately the same blue as `cpu`/`memory` rather than the PRD's cyan:
    /// cyan next to the muted upload orange read as a third unrelated hue in the
    /// popup, and the app now leans on shape (stacked vs. mirrored bars) and the
    /// card's title to tell metrics apart, not on giving each one its own color.
    static let network = Color.blue
    /// Network's upload-direction data color. A muted orange, not the system
    /// `Color.orange`: at full saturation it fought the download blue for
    /// attention in the mirrored chart, where the two are stacked against a
    /// shared baseline and neither direction is the more important one.
    ///
    /// Kept a distinct token from `warning` rather than a reuse of it, even
    /// though both are orange-ish: `warning` is load-bearing status-pill
    /// semantics (CPU/storage/battery/temperature all tint their pill for
    /// "warning"), while this is a plain data-series color — network has no
    /// threshold policy and never shows a status pill.
    static let networkUpload = Color(red: 0.875, green: 0.563, blue: 0.125)
    /// Both network series are pulled back slightly rather than drawn at full strength.
    /// The mirrored chart fills from a shared baseline in *both* directions at once, so
    /// at full opacity the two bands read as solid slabs of color; easing off lets the
    /// gridline and baseline stay visible through them without washing the series out.
    static let networkSeriesOpacity: Double = 0.8
    static let battery = Color.green
    static let gpu = Color.teal
    /// Pink is the only unclaimed system hue distinct from every other metric
    /// and from the orange/red reserved for warning/critical.
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

/// Tuning shared by every history chart — the CPU/Memory hero cards, the Network card's
/// mirrored chart, and the menu bar popup's copies of all three.
nonisolated enum MetricChartLayout {
    /// Matches the ring buffer capacity used by `MetricsEngine`/`FixtureMetricsTickFeed`
    /// retain history in, and the "60s...now" axis labels below each chart.
    static let historyWindowSize = MetricHistoryDefaults.sampleCapacity

    /// Fraction of each bar's slot the bar itself occupies — the remainder is
    /// always a gap, whether the slot is wide (big window) or narrow (small
    /// window), instead of a fixed point value that either wastes space on a
    /// big card or disappears on a small one.
    static let barWidthFraction: CGFloat = 0.85
    /// The mirrored network chart runs its bars slightly narrower than the stacked
    /// charts. It draws in both directions from a shared baseline, so it needs a
    /// visible gap between bars to still read as a series of samples — pushed much
    /// past this the gap falls below a pixel at popup width and the bars fuse into
    /// one continuous band.
    static let mirroredBarWidthFraction: CGFloat = 0.75
    static let minimumBarWidth: CGFloat = 2

    /// Rounding on a bar's outer end. Deliberately slight: at 60 bars across a
    /// popup-sized chart the bars are only a few points wide, so a radius near
    /// half that width domes every bar into a lozenge and reads as noise rather
    /// than as a bar.
    static let barCornerRadius: CGFloat = 1

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

import SwiftUI

/// A small standalone card for OS-reported memory pressure — split out from the
/// Memory hero card (rather than a row inside it) so it sits in the regular
/// single-width card grid alongside Storage/Network/Battery/GPU instead of being
/// squeezed into the memory card's fixed hero+legend width. Not part of the
/// `MetricKind`/`MetricCardModel` system: memory pressure isn't a separate domain
/// metric with its own reader/history, just `MemorySnapshot.pressure` surfaced a
/// second way, so it takes the already-derived `MetricCardStatus?` directly.
struct MemoryPressureCardView: View {
    let status: MetricCardStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: MetricSpacing.headerSpacing) {
            Label("Memory Pressure", systemImage: "gauge.medium")
                .font(MetricTypography.label)
                .foregroundStyle(MetricPalette.memory)

            Spacer(minLength: 4)

            HStack {
                Spacer()
                MemoryPressureGaugeView(status: status)
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .metricCardBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memory Pressure")
        .accessibilityValue(accessibilityWord)
        .accessibilityIdentifier("dashboard.card.memoryPressure")
    }

    private var accessibilityWord: String {
        switch status {
        case .none: "Unavailable"
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

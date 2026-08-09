import SwiftUI

/// The menu bar popup's Storage detail: a large usage ring with the percentage
/// centered inside it, plus a total/used/free breakdown to its side. Storage has
/// no history to chart, so this replaces the sparkline the other metrics show here.
struct StorageUsageDetailView: View {
    let fraction: Double?
    let detail: StorageUsageDetail
    let color: Color
    let formatter: MetricFormatter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ringDiameter: CGFloat = 120
    private static let ringLineWidth: CGFloat = 12
    /// The ring sits inside the popup's clipped transition stage. Leave room for the stroke's
    /// outer half so the left edge stays round instead of being cut by that stage boundary.
    private static let detailSpacing: CGFloat = 18

    var body: some View {
        HStack(spacing: Self.detailSpacing) {
            ring
                .padding(.leading, Self.ringLineWidth / 2)

            VStack(alignment: .leading, spacing: 16) {
                row(label: "Total Capacity", value: detail.totalText)
                row(label: "Used Space", value: detail.usedText)
                row(label: "Free Space", value: detail.freeText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: Self.ringLineWidth)

            if let fraction {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: Self.ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: fraction)
            }

            Text(formatter.percentage(fraction))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: fraction)
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
    }

    private func row(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
        }
    }
}

#Preview {
    StorageUsageDetailView(
        fraction: 0.88,
        detail: StorageUsageDetail(totalText: "245.11 GB", usedText: "217.74 GB", freeText: "27.37 GB"),
        color: MetricPalette.storage,
        formatter: MetricFormatter()
    )
    .padding()
    .frame(width: 360, height: 200)
}

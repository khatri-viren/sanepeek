import SwiftUI

/// Storage is the one card that shows a used/total fraction instead of a
/// history sparkline, matching the PRD's circular usage indicator.
struct StorageUsageRing: View {
    let fraction: Double?
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 8)

            if let fraction {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: fraction)
            }
        }
        .frame(width: 56, height: 56)
    }
}

import SwiftUI

/// A semicircular green/yellow/red dial for OS-reported memory pressure, mirroring the
/// dial widget common third-party menu-bar memory monitors use. `StorageUsageRing` is the
/// existing precedent in this codebase for a custom-drawn circular indicator; this follows
/// the same self-contained `Path`/`Shape` style.
///
/// Unlike `MetricCardStatus`'s pill presentation (which stays neutral/wordless at `.normal`
/// so color is never the only signal for an *escalation*), this gauge is explicitly a
/// traffic-light instrument — showing a green zone and the word "Normal" is the entire point,
/// so its color/label mapping is its own, not reused from `MetricCardStatus`.
struct MemoryPressureGaugeView: View {
    let status: MetricCardStatus?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            dial
                .frame(width: 120, height: 60)

            Text(label)
                .font(MetricTypography.secondaryMetric.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private var dial: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height)
            let radius = min(proxy.size.width / 2, proxy.size.height) - 6

            ZStack {
                zoneArc(center: center, radius: radius, startDegrees: 180, endDegrees: 240, zoneColor: MetricPalette.pressureNormal)
                zoneArc(center: center, radius: radius, startDegrees: 240, endDegrees: 300, zoneColor: MetricPalette.warning)
                zoneArc(center: center, radius: radius, startDegrees: 300, endDegrees: 360, zoneColor: MetricPalette.critical)

                if status != nil {
                    needle(center: center, radius: radius)
                        .rotationEffect(.degrees(needleRotation), anchor: .bottom)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: needleRotation)
                }
            }
        }
    }

    /// Zones are always drawn at full color as the dial's fixed instrument face; when
    /// `status` is nil (pressure not yet available) they fall back to `idleFill` instead,
    /// the same "no data yet" swatch the Memory legend already uses for its Free row.
    private func zoneArc(center: CGPoint, radius: CGFloat, startDegrees: Double, endDegrees: Double, zoneColor: Color) -> some View {
        Path { path in
            path.addArc(center: center, radius: radius, startAngle: .degrees(startDegrees), endAngle: .degrees(endDegrees), clockwise: false)
        }
        .stroke(status == nil ? MetricPalette.idleFill : zoneColor, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
    }

    private func needle(center: CGPoint, radius: CGFloat) -> some View {
        Path { path in
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius + 8))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    /// -60/0/+60 degrees from straight up, landing the needle in the center of the
    /// normal/warning/critical zone respectively.
    private var needleRotation: Double {
        switch status {
        case .none: 0
        case .normal: -60
        case .warning: 0
        case .critical: 60
        }
    }

    private var color: Color {
        switch status {
        case .none: .secondary
        case .normal: MetricPalette.pressureNormal
        case .warning: MetricPalette.warning
        case .critical: MetricPalette.critical
        }
    }

    private var label: String {
        switch status {
        case .none: "--"
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

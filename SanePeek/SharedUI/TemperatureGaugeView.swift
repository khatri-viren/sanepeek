import SwiftUI

/// A continuous-value needle dial for CPU/GPU temperature — distinct from
/// `MemoryPressureGaugeView`, which only positions a needle at 3 fixed states for a
/// discrete OS-reported enum. Temperature is a real number, so both the needle position
/// and the zone-band boundaries are computed from actual °C thresholds, matching the
/// same `addArc`/`rotationEffect(anchor: .bottom)` convention `MemoryPressureGaugeView`
/// already established: angle 180°=left, 270°=up, 360°=right, and
/// `rotationEffect` degrees = arc-angle - 270 (needle is drawn pointing straight up).
struct TemperatureGaugeView: View {
    let celsius: Double?
    let valueText: String

    private let minCelsius = 30.0
    private let warningCelsius = 80.0
    private let criticalCelsius = 95.0
    private let maxCelsius = 105.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            dial
                .frame(width: 120, height: 60)

            Text(celsius == nil ? "--" : valueText)
                .font(MetricTypography.secondaryMetric.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private var dial: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height)
            let radius = min(proxy.size.width / 2, proxy.size.height) - 6

            ZStack {
                zoneArc(center: center, radius: radius, start: 180, end: degrees(for: warningCelsius), zoneColor: MetricPalette.pressureNormal)
                zoneArc(center: center, radius: radius, start: degrees(for: warningCelsius), end: degrees(for: criticalCelsius), zoneColor: MetricPalette.warning)
                zoneArc(center: center, radius: radius, start: degrees(for: criticalCelsius), end: 360, zoneColor: MetricPalette.critical)

                if let celsius {
                    needle(center: center, radius: radius)
                        .rotationEffect(.degrees(degrees(for: celsius) - 270), anchor: .bottom)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: celsius)
                }
            }
        }
    }

    /// Maps a celsius value onto the dial's 180°...360° semicircle sweep, clamped to
    /// the gauge's displayed range.
    private func degrees(for value: Double) -> Double {
        let clamped = min(max(value, minCelsius), maxCelsius)
        return 180 + (clamped - minCelsius) / (maxCelsius - minCelsius) * 180
    }

    /// Zones fall back to `idleFill` gray when `celsius` is nil (temperature not yet
    /// available), the same "no data yet" swatch used elsewhere in the dashboard.
    private func zoneArc(center: CGPoint, radius: CGFloat, start: Double, end: Double, zoneColor: Color) -> some View {
        Path { path in
            path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        }
        .stroke(celsius == nil ? MetricPalette.idleFill : zoneColor, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
    }

    private func needle(center: CGPoint, radius: CGFloat) -> some View {
        Path { path in
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius + 8))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    private var color: Color {
        guard let celsius else { return .secondary }
        if celsius >= criticalCelsius { return MetricPalette.critical }
        if celsius >= warningCelsius { return MetricPalette.warning }
        return MetricPalette.pressureNormal
    }
}

import Charts
import SwiftUI

/// Live `MenuBarExtra` label content for one metric: either its current formatted value
/// ("number" mode) or a miniaturized trailing-window bar chart ("bar" mode), per the user's
/// per-metric `MenuBarDisplayMode` choice in Settings.
///
/// Takes `appState` + `kind` rather than a precomputed card/mode, and reads them inside its own
/// `body` rather than as arguments the caller evaluates up front: this label's data changes on
/// every metrics tick, and evaluating it eagerly inside `SanePeekApp.body` (a `Scene`, not a
/// `View`) forced the *entire* scene graph — every `MenuBarExtra`, the dashboard `WindowGroup`,
/// `Settings` — to reconstruct on every tick, which pinned the main thread. Reading the
/// `@Observable` state from within a `View`'s own `body` is the well-supported path for
/// frequent updates; only `View.body` is optimized for that, `Scene.body` is not.
///
/// Reuses `MetricCardStatus.tintColor` directly rather than a new color rule — the same
/// normal/warning/critical resolution already used for every dashboard card's status pill.
/// `MetricCardStatus` documents "conveyed via symbol *and* word everywhere it's shown, never
/// color alone"; a menu bar item has no room for the word, so the status symbol is shown as a
/// small badge alongside the tint instead of dropping that principle for this surface.
struct MenuBarMetricLabel: View {
    let appState: AppState
    let kind: MetricKind

    /// Menu bar width is tight, so this trails a much shorter window than the dashboard
    /// charts' `MetricChartLayout.historyWindowSize` (60).
    private static let historyWindowSize = 16

    var body: some View {
        let card = appState.dashboardViewModel.card(for: kind)
        let displayMode = appState.settingsStore.menuBarConfig(for: kind).displayMode

        HStack(spacing: 3) {
            content(card: card, displayMode: displayMode)

            if let symbolName = card?.status?.symbolName, let tint = card?.status?.tintColor {
                Image(systemName: symbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
            }
        }
        .foregroundStyle(card?.status?.tintColor ?? .primary)
    }

    @ViewBuilder
    private func content(card: MetricCardModel?, displayMode: MenuBarDisplayMode) -> some View {
        switch displayMode {
        case .number:
            Text(card?.primaryValue ?? "--")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        case .bar:
            barChart(card: card)
                .frame(width: 28, height: 14)
        }
    }

    private func barChart(card: MetricCardModel?) -> some View {
        let history = Array((card?.sparklineValues ?? []).suffix(Self.historyWindowSize))
        // Self-scaled to the visible window's own peak rather than a fixed domain: history
        // magnitudes vary by metric (a 0...1 fraction, bytes/sec, degrees Celsius), and this
        // glance-sized chart only needs to convey trend/shape, not an absolute axis. The tiny
        // epsilon only guards against a degenerate 0...0 domain when every sample is zero.
        let domainMax = max(history.max() ?? 0, 0.0001)

        return Chart {
            ForEach(Array(history.enumerated()), id: \.offset) { index, value in
                BarMark(x: .value("Tick", index), y: .value("Value", value), width: .fixed(2))
                    .cornerRadius(0.5)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...domainMax)
        .chartLegend(.hidden)
        .foregroundStyle(card?.status?.tintColor ?? .primary)
    }
}

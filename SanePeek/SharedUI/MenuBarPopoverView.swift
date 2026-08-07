import AppKit
import SwiftUI

/// The Control Center–style popup shown when a menu bar item is clicked: a compact glance at
/// every metric, regardless of which ones are actually enabled in the menu bar itself (V1.1
/// plan 3c — this is a full glance view, not scoped to the menu bar subset), plus a footer
/// button to open the full dashboard.
///
/// Reports its own visibility to `AppState` via `onAppear`/`onDisappear`, which temporarily
/// widens `MetricsEngine`'s active-metric set to all seven for as long as the popup is open.
struct MenuBarPopoverView: View {
    let appState: AppState

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// Mirrors the dashboard's visual grouping (hero cards first, then the generic ones) so
    /// the popup reads consistently with the full dashboard rather than declaration order.
    private static let displayOrder: [MetricKind] = [.cpu, .memory, .temperature, .network, .storage, .battery, .gpu]

    private var viewModel: DashboardViewModel { appState.dashboardViewModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SanePeek")
                    .font(.headline)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                ForEach(Self.displayOrder, id: \.self) { kind in
                    if let card = viewModel.card(for: kind) {
                        CompactMetricRowView(model: card)
                    }
                }
            }

            Divider()

            Button {
                openWindow(id: WindowID.dashboard)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Open Dashboard")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear { appState.handlePopupVisibilityChange(isVisible: true) }
        .onDisappear { appState.handlePopupVisibilityChange(isVisible: false) }
    }
}

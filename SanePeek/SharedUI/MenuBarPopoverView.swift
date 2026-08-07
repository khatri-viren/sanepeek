import AppKit
import SwiftUI

/// The Control Center–style popup shown when a menu bar item is clicked: a compact glance at
/// every metric, regardless of which ones are actually enabled in the menu bar itself (V1.1
/// plan 3c — this is a full glance view, not scoped to the menu bar subset), plus header
/// buttons to open the full dashboard and settings.
///
/// Each row doubles as a tab: selecting one drives `PopoverMetricChartView` on the right, so
/// the list and the chart live in one side-by-side popup instead of two separate concepts.
///
/// Reports its own visibility to `AppState` via `onAppear`/`onDisappear`, which temporarily
/// widens `MetricsEngine`'s active-metric set to all seven for as long as the popup is open.
struct MenuBarPopoverView: View {
    let appState: AppState
    /// The menu bar item this popup belongs to. Every enabled metric declares its own
    /// `MenuBarExtra` and therefore its own copy of this view, so the popup opens on the
    /// metric whose item was actually clicked rather than always on CPU.
    let kind: MetricKind

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMetric: MetricKind

    /// Mirrors the dashboard's visual grouping (hero cards first, then the generic ones) so
    /// the popup reads consistently with the full dashboard rather than declaration order.
    private static let displayOrder: [MetricKind] = [.cpu, .memory, .temperature, .network, .storage, .battery, .gpu]
    /// Wide enough for the longest title/value pair ("Temperature" + "-40.0 °C") to sit on
    /// one line — at a narrower width "Temperature" wrapped mid-word.
    private static let rowListWidth: CGFloat = 210
    /// Rounder than the system's own menu bar popover corner (~14pt).
    private static let windowCornerRadius: CGFloat = 24

    init(appState: AppState, kind: MetricKind) {
        self.appState = appState
        self.kind = kind
        _selectedMetric = State(initialValue: kind)
    }

    private var viewModel: DashboardViewModel { appState.dashboardViewModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("SanePeek")
                    .font(.headline)

                Spacer()

                Button {
                    openWindow(id: WindowID.dashboard)
                    // The app is an accessory (`LSUIElement`), so opening a window doesn't
                    // bring it forward on its own.
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .help("Open Dashboard")
                .accessibilityLabel("Open Dashboard")

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
            }

            HStack(alignment: .top, spacing: 16) {
                rowList
                    .frame(width: Self.rowListWidth)

                if let selectedCard = viewModel.card(for: selectedMetric) {
                    PopoverMetricChartView(
                        model: selectedCard,
                        viewModel: viewModel,
                        formatter: appState.settingsStore.formatter
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            // Keeps the popup's height steady as the selection moves between metrics with
            // and without a legend row, instead of resizing under the pointer.
            .frame(height: 260)
        }
        .padding(16)
        .frame(width: 560)
        .background(WindowAccessor(onResolve: roundWindowCorners))
        .onAppear {
            // The window is reused across openings, so `selectedMetric` still holds whatever
            // was picked last time — reset it, or clicking Memory would reopen on whichever
            // tab the previous session ended on.
            selectedMetric = kind
            appState.handlePopupVisibilityChange(isVisible: true, kind: kind)
        }
        .onDisappear { appState.handlePopupVisibilityChange(isVisible: false, kind: kind) }
        // macOS leaves an already-open popup on screen when a *different* menu bar item is
        // clicked, so each popup closes itself when another one takes over. Dismissing through
        // the environment action rather than closing the `NSWindow` directly keeps
        // `MenuBarExtra`'s own presented-state in sync — closing the window behind its back
        // leaves it believing the popup is still up, so the next click on that item only
        // toggles the stale flag and appears to do nothing.
        .onChange(of: appState.frontmostPopupKind) { _, frontmost in
            if let frontmost, frontmost != kind {
                dismiss()
            }
        }
    }

    /// Rounds the popover window itself past the system default.
    ///
    /// There is no property to set: on macOS 26 the popup's Liquid Glass background — corner
    /// arc included — is rendered by an `SDFLayer` the system owns, and the window has no
    /// `NSVisualEffectView` to restyle. So this clips the window's frame view instead, which
    /// masks the system's glass to a rounder rect.
    private func roundWindowCorners(_ window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = Self.windowCornerRadius
        frameView.layer?.cornerCurve = .continuous
        frameView.layer?.masksToBounds = true
    }

    private var rowList: some View {
        VStack(spacing: 6) {
            ForEach(Self.displayOrder, id: \.self) { kind in
                if let card = viewModel.card(for: kind) {
                    Button {
                        selectedMetric = kind
                    } label: {
                        CompactMetricRowView(model: card, isSelected: selectedMetric == kind)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview("Menu Bar Popover") {
    MenuBarPopoverView(appState: AppState(dependencies: .preview), kind: .cpu)
}

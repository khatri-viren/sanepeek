import AppKit
import SwiftUI

/// The Control Center–style popup shown when a menu bar item is clicked: a compact glance at
/// every metric, regardless of which ones are actually enabled in the menu bar itself, plus
/// controls for Settings and quitting the agent.
///
/// Each row doubles as a tab: selecting one drives `PopoverMetricChartView` on the right, so
/// the list and the chart live in one side-by-side popup instead of two separate concepts.
///
/// Its AppKit owner reports visibility to `AppState`. The selected detail is owned by that
/// controller so a menu-bar handoff can update this live view without recreating its window.
struct MenuBarPopoverView: View {
    let appState: AppState
    let selection: MenuBarDetailSelection
    let onSelectedMetricChange: (MetricKind) -> Void
    let onOpenSettings: () -> Void

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wide enough for the longest title/value pair ("Temperature" + "-40.0 °C") to sit on
    /// one line — at a narrower width "Temperature" wrapped mid-word.
    private static let rowListWidth: CGFloat = 210

    init(
        appState: AppState,
        selection: MenuBarDetailSelection,
        onSelectedMetricChange: @escaping (MetricKind) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.selection = selection
        self.onSelectedMetricChange = onSelectedMetricChange
        self.onOpenSettings = onOpenSettings
    }

    private var viewModel: MetricsViewModel { appState.metricsViewModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("SanePeek")
                    .font(.headline)

                Spacer()

                Button {
                    onOpenSettings()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                // A menu-bar popover becomes key when it opens, which otherwise leaves the
                // first header button with a persistent blue keyboard-focus treatment.
                .focusEffectDisabled()
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("popup.settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Quit SanePeek")
                .accessibilityLabel("Quit SanePeek")
                .accessibilityIdentifier("popup.quit")
            }

            HStack(alignment: .top, spacing: 16) {
                rowList
                    .frame(width: Self.rowListWidth)

                chartStage
            }
            // Keeps the popup's height steady as the selection moves between metrics with
            // and without a legend row, instead of resizing under the pointer.
            .frame(height: 260)
        }
        .padding(16)
        .frame(width: 560)
        .accessibilityIdentifier("monitor.window")
        // The AppKit popover supplies the panel; setting the hosting window's appearance keeps
        // the panel and SwiftUI foreground colors aligned with the app preference.
        .background(WindowAppearanceAccessor(colorScheme: appState.settingsStore.appearance.colorScheme))
    }

    private var rowList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MenuBarCatalog.popoverOrder, id: \.self) { kind in
                if let card = viewModel.card(for: kind) {
                    Button {
                        select(kind)
                    } label: {
                        CompactMetricRowView(model: card, isSelected: selection.kind == kind)
                    }
                    .buttonStyle(.plain)
                    // The row's visual content includes flexible empty space. Keep the
                    // button's hit target across the full list width rather than only over
                    // the icon/title/value glyphs.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Keeps the chart panel anchored while its contents cross-fade/slide between tabs. `.id`
    /// forces a fresh `PopoverMetricChartView` per metric (rather than an update to the same
    /// instance), which pairs with `.transition` to animate a real insert/remove instead of a
    /// data change — the latter is what let Swift Charts' own per-mark animation take over.
    private var chartStage: some View {
        ZStack(alignment: .topLeading) {
            if let selectedCard = viewModel.card(for: selection.kind) {
                PopoverMetricChartView(
                    model: selectedCard,
                    viewModel: viewModel,
                    formatter: appState.settingsStore.formatter
                )
                .id(selection.kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(chartTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var chartTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: 18).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
            removal: .offset(x: -18).combined(with: .opacity).combined(with: .scale(scale: 0.98))
        )
    }

    private func select(_ kind: MetricKind) {
        guard kind != selection.kind else { return }
        onSelectedMetricChange(kind)
    }

}

#Preview("Menu Bar Popover") {
    MenuBarPopoverView(
        appState: AppState(dependencies: .preview),
        selection: MenuBarDetailSelection(kind: .cpu)
    )
}

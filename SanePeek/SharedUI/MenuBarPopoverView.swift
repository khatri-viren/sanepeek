import AppKit
import SwiftUI

/// The Control Center–style popup shown when a menu bar item is clicked: a compact glance at
/// every metric, regardless of which ones are actually enabled in the menu bar itself, plus
/// controls for Settings and quitting the agent.
///
/// Each row doubles as a tab: selecting one drives `PopoverMetricChartView` on the right, so
/// the list and the chart live in one side-by-side popup instead of two separate concepts.
///
/// Its AppKit owner reports visibility to `AppState`; this SwiftUI view is created only while
/// that one shared popover is presented.
struct MenuBarPopoverView: View {
    let appState: AppState
    /// The status item that opened the shared popover. It seeds the first selected metric.
    let kind: MetricKind

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMetric: MetricKind

    /// Wide enough for the longest title/value pair ("Temperature" + "-40.0 °C") to sit on
    /// one line — at a narrower width "Temperature" wrapped mid-word.
    private static let rowListWidth: CGFloat = 210

    init(appState: AppState, kind: MetricKind) {
        self.appState = appState
        self.kind = kind
        _selectedMetric = State(initialValue: kind)
    }

    private var viewModel: MetricsViewModel { appState.metricsViewModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("SanePeek")
                    .font(.headline)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("popup.settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
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
                        CompactMetricRowView(model: card, isSelected: selectedMetric == kind)
                    }
                    .buttonStyle(.plain)
                    // The row's visual content includes flexible empty space. Keep the
                    // button's hit target across the full list width rather than only over
                    // the icon/title/value glyphs.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("popup.metric.\(kind.rawValue)")
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
            if let selectedCard = viewModel.card(for: selectedMetric) {
                PopoverMetricChartView(
                    model: selectedCard,
                    viewModel: viewModel,
                    formatter: appState.settingsStore.formatter
                )
                .id(selectedMetric)
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
        guard kind != selectedMetric else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.18)) {
            selectedMetric = kind
        }
    }

}

#Preview("Menu Bar Popover") {
    MenuBarPopoverView(appState: AppState(dependencies: .preview), kind: .cpu)
}

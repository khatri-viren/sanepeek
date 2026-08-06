//
//  DashboardView.swift
//  SanePeek
//

import SwiftUI

struct DashboardView: View {
    @Environment(\.openSettings) private var openSettings

    let appState: AppState
    @State private var viewModel: DashboardViewModel

    init(appState: AppState) {
        self.appState = appState
        let settingsStore = appState.settingsStore
        _viewModel = State(initialValue: DashboardViewModel(
            feed: appState.dependencies.makeDashboardTickFeed(),
            formatterProvider: { settingsStore.formatter }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SanePeek")
                        .font(.title2.weight(.semibold))

                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Open Settings")
                .accessibilityIdentifier("dashboard.settings")
            }

            Divider()

            if !viewModel.hasReceivedData {
                ContentUnavailableView(
                    "Monitoring is getting ready",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Metric cards will appear here as the monitoring engine comes online.")
                )
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    // The CPU and Memory cards are twice as wide as their
                    // siblings, so they reflow with them rather than sitting in
                    // full-width rows of their own above the grid.
                    MetricCardFlowLayout {
                        CPUCardView(model: viewModel.cpuCard, detail: viewModel.cpuDetail)
                            .metricCardSpan(2)

                        MemoryCardView(model: viewModel.memoryCard, detail: viewModel.memoryDetail)
                            .metricCardSpan(2)

                        TemperatureCardView(model: viewModel.temperatureCard, detail: viewModel.temperatureDetail)
                            .metricCardSpan(2)

                        MemoryPressureCardView(status: viewModel.memoryCard.status)
                            .frame(maxHeight: .infinity, alignment: .top)

                        ForEach(viewModel.cards) { card in
                            MetricCardView(model: card) {
                                trailingView(for: card)
                            }
                            // Fill the row height the layout offers, so cards
                            // sharing a row line up at the bottom instead of
                            // ending wherever their own content happens to.
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 420)
        .dynamicTypeSize(.large ... .xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.root")
    }

    @ViewBuilder
    private func trailingView(for card: MetricCardModel) -> some View {
        if let usageFraction = card.usageFraction {
            StorageUsageRing(fraction: usageFraction, color: card.accentColor)
        } else if !card.sparklineValues.isEmpty {
            // A `Chart` has no intrinsic width, so bound it: the hero value
            // (higher layout priority) takes what it needs and the sparkline
            // gets the rest, without collapsing to a sliver on a narrow card
            // or stretching past the value on a wide one.
            SparklineView(values: card.sparklineValues, color: card.accentColor)
                .frame(minWidth: 72, maxWidth: 140)
        } else {
            EmptyView()
        }
    }

    private var statusMessage: String {
        switch appState.dependencies.runtime {
        case .live:
            "Ready to monitor your Mac"
        case .preview:
            "Preview data"
        }
    }
}

#Preview("Normal") {
    DashboardView(appState: AppState(dependencies: AppDependencies(runtime: .preview, fixtureSnapshot: MetricFixtures.dashboard())))
}

#Preview("Warning") {
    DashboardView(appState: AppState(dependencies: AppDependencies(runtime: .preview, fixtureSnapshot: MetricFixtures.warning())))
}

#Preview("Critical") {
    DashboardView(appState: AppState(dependencies: AppDependencies(runtime: .preview, fixtureSnapshot: MetricFixtures.critical())))
}

#Preview("Unavailable") {
    DashboardView(appState: AppState(dependencies: AppDependencies(runtime: .preview, fixtureSnapshot: MetricFixtures.unavailable())))
}

#Preview("Dark Appearance") {
    DashboardView(appState: AppState(dependencies: .preview))
        .preferredColorScheme(.dark)
}

#Preview("Light Appearance") {
    DashboardView(appState: AppState(dependencies: .preview))
        .preferredColorScheme(.light)
}

#Preview("Minimum Window Size") {
    DashboardView(appState: AppState(dependencies: .preview))
        .frame(width: 720, height: 420)
}

#Preview("Reduced Motion") {
    let reduceMotionKeyPath = \EnvironmentValues.accessibilityReduceMotion as! WritableKeyPath<EnvironmentValues, Bool>
    DashboardView(appState: AppState(dependencies: .preview))
        .environment(reduceMotionKeyPath, true)
}

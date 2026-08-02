//
//  DashboardView.swift
//  SanePeek
//

import SwiftUI

struct DashboardView: View {
    @Environment(\.openSettings) private var openSettings

    let appState: AppState
    @State private var viewModel: DashboardViewModel

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: MetricSpacing.gridSpacing)]

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

            if viewModel.cards.isEmpty {
                ContentUnavailableView(
                    "Monitoring is getting ready",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Metric cards will appear here as the monitoring engine comes online.")
                )
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: MetricSpacing.gridSpacing) {
                        ForEach(viewModel.cards) { card in
                            MetricCardView(model: card) {
                                trailingView(for: card)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.root")
    }

    @ViewBuilder
    private func trailingView(for card: MetricCardModel) -> some View {
        if let usageFraction = card.usageFraction {
            StorageUsageRing(fraction: usageFraction, color: card.accentColor)
        } else if !card.sparklineValues.isEmpty {
            SparklineView(values: card.sparklineValues, color: card.accentColor)
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

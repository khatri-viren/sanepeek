//
//  DashboardView.swift
//  SanePeek
//

import SwiftUI

struct DashboardView: View {
    @Environment(\.openSettings) private var openSettings

    let appState: AppState

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

            ContentUnavailableView(
                "Monitoring is getting ready",
                systemImage: "chart.bar.xaxis",
                description: Text("Metric cards will appear here as the monitoring engine comes online.")
            )

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.root")
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

#Preview {
    DashboardView(appState: AppState(dependencies: .preview))
}

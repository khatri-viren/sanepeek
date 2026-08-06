//
//  SanePeekApp.swift
//  SanePeek
//

import SwiftUI

@main
struct SanePeekApp: App {
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    init() {
        self.init(dependencies: .forLaunch())
    }

    init(dependencies: AppDependencies) {
        _appState = State(initialValue: AppState(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(appState: appState)
                .preferredColorScheme(appState.settingsStore.appearance.colorScheme)
        }
        .defaultSize(width: 1100, height: 900)
        .onChange(of: scenePhase) { _, newPhase in
            appState.handlePollingVisibilityChange(isVisible: newPhase == .active)
        }

        Settings {
            SettingsView(settingsStore: appState.settingsStore)
                .preferredColorScheme(appState.settingsStore.appearance.colorScheme)
        }
    }
}

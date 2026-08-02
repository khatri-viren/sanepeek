//
//  SanePeekApp.swift
//  SanePeek
//

import SwiftUI

@main
struct SanePeekApp: App {
    @State private var appState: AppState

    init() {
        self.init(dependencies: .live)
    }

    init(dependencies: AppDependencies) {
        _appState = State(initialValue: AppState(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(appState: appState)
        }
        .defaultSize(width: 840, height: 520)

        Settings {
            SettingsView()
        }
    }
}

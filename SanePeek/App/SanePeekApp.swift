//
//  SanePeekApp.swift
//  SanePeek
//

import SwiftUI

@main
struct SanePeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState: AppState
    @State private var updater = UpdaterController()

    init() {
        self.init(dependencies: .forLaunch())
    }

    init(dependencies: AppDependencies) {
        _appState = State(initialValue: AppState(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup(id: WindowID.dashboard) {
            DashboardView(appState: appState, dockIconController: appDelegate.dockIconController)
                .preferredColorScheme(appState.settingsStore.appearance.colorScheme)
                .background(
                    MenuBarPopoverControllerInstaller(
                        controller: appDelegate.menuBarPopoverController,
                        appState: appState
                    )
                )
        }
        .defaultSize(width: 1100, height: 900)

        Settings {
            SettingsView(settingsStore: appState.settingsStore, updater: updater)
                .preferredColorScheme(appState.settingsStore.appearance.colorScheme)
        }
    }
}

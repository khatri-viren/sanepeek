//
//  SanePeekApp.swift
//  SanePeek
//

import SwiftUI

@main
struct SanePeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var updater = UpdaterController()

    var body: some Scene {
        Settings {
            SettingsView(settingsStore: appDelegate.appState.settingsStore, updater: updater)
                .preferredColorScheme(appDelegate.appState.settingsStore.appearance.colorScheme)
        }
    }
}

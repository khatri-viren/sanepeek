//
//  SanePeekApp.swift
//  SanePeek
//

import SwiftUI

@main
struct SanePeekApp: App {
    @State private var appState: AppState

    init() {
        self.init(dependencies: .forLaunch())
    }

    init(dependencies: AppDependencies) {
        _appState = State(initialValue: AppState(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup(id: WindowID.dashboard) {
            DashboardView(appState: appState)
                .preferredColorScheme(appState.settingsStore.appearance.colorScheme)
        }
        .defaultSize(width: 1100, height: 900)

        Settings {
            SettingsView(settingsStore: appState.settingsStore)
                .preferredColorScheme(appState.settingsStore.appearance.colorScheme)
        }

        // One static scene per `MetricKind`, each gated by that metric's enabled flag —
        // `Scene` builders have no `ForEach` the way `View` builders do, so a dynamic-length
        // collection of menu bar items isn't an option; declaring all seven and toggling
        // `isInserted` is the supported way to make the set configurable (V1.1 plan 3f).
        MenuBarExtra(isInserted: menuBarEnabledBinding(for: .cpu)) {
            MenuBarPopoverView(appState: appState)
        } label: {
            MenuBarMetricLabel(appState: appState, kind: .cpu)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: menuBarEnabledBinding(for: .memory)) {
            MenuBarPopoverView(appState: appState)
        } label: {
            MenuBarMetricLabel(appState: appState, kind: .memory)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: menuBarEnabledBinding(for: .storage)) {
            MenuBarPopoverView(appState: appState)
        } label: {
            MenuBarMetricLabel(appState: appState, kind: .storage)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: menuBarEnabledBinding(for: .network)) {
            MenuBarPopoverView(appState: appState)
        } label: {
            MenuBarMetricLabel(appState: appState, kind: .network)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: menuBarEnabledBinding(for: .battery)) {
            MenuBarPopoverView(appState: appState)
        } label: {
            MenuBarMetricLabel(appState: appState, kind: .battery)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: menuBarEnabledBinding(for: .gpu)) {
            MenuBarPopoverView(appState: appState)
        } label: {
            MenuBarMetricLabel(appState: appState, kind: .gpu)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: menuBarEnabledBinding(for: .temperature)) {
            MenuBarPopoverView(appState: appState)
        } label: {
            MenuBarMetricLabel(appState: appState, kind: .temperature)
        }
        .menuBarExtraStyle(.window)
    }

    private func menuBarEnabledBinding(for kind: MetricKind) -> Binding<Bool> {
        Binding(
            get: { appState.settingsStore.menuBarConfig(for: kind).isEnabled },
            set: { newValue in
                var config = appState.settingsStore.menuBarConfig(for: kind)
                config.isEnabled = newValue
                appState.settingsStore.setMenuBarConfig(config, for: kind)
            }
        )
    }
}

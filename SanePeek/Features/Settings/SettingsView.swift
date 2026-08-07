//
//  SettingsView.swift
//  SanePeek
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $settingsStore.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance")
            }

            Section("Monitoring") {
                Picker("Refresh Rate", selection: $settingsStore.refreshRate) {
                    ForEach(RefreshRate.allCases, id: \.self) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .accessibilityIdentifier("settings.refreshRate")

                Picker("Byte Units", selection: $settingsStore.byteUnitSystem) {
                    ForEach(ByteUnitSystem.allCases, id: \.self) { system in
                        Text(system.displayName).tag(system)
                    }
                }
                .accessibilityIdentifier("settings.byteUnitSystem")

                Picker("Temperature", selection: $settingsStore.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .accessibilityIdentifier("settings.temperatureUnit")
            }

            Section("Menu Bar") {
                ForEach(MenuBarSettingsRow.allRows) { row in
                    menuBarRow(for: row)
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .accessibilityIdentifier("settings.launchAtLogin")

                if let message = launchAtLoginStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.launchAtLoginStatus")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .navigationTitle("Settings")
        .dynamicTypeSize(.large ... .xxxLarge)
        .accessibilityIdentifier("settings.root")
        .onAppear { settingsStore.refreshLaunchAtLoginStatus() }
    }

    private func menuBarRow(for row: MenuBarSettingsRow) -> some View {
        HStack {
            Toggle(row.title, isOn: menuBarEnabledBinding(for: row.kind))
                .accessibilityIdentifier("settings.menuBar.\(row.kind.rawValue).enabled")

            Spacer()

            Picker("", selection: menuBarModeBinding(for: row.kind)) {
                ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            .disabled(!settingsStore.menuBarConfig(for: row.kind).isEnabled)
            .accessibilityIdentifier("settings.menuBar.\(row.kind.rawValue).mode")
        }
    }

    private func menuBarEnabledBinding(for kind: MetricKind) -> Binding<Bool> {
        Binding(
            get: { settingsStore.menuBarConfig(for: kind).isEnabled },
            set: { newValue in
                var config = settingsStore.menuBarConfig(for: kind)
                config.isEnabled = newValue
                settingsStore.setMenuBarConfig(config, for: kind)
            }
        )
    }

    private func menuBarModeBinding(for kind: MetricKind) -> Binding<MenuBarDisplayMode> {
        Binding(
            get: { settingsStore.menuBarConfig(for: kind).displayMode },
            set: { newValue in
                var config = settingsStore.menuBarConfig(for: kind)
                config.displayMode = newValue
                settingsStore.setMenuBarConfig(config, for: kind)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                switch settingsStore.launchAtLoginStatus {
                case .enabled, .requiresApproval: true
                case .notRegistered, .notFound, .failed: false
                }
            },
            set: { settingsStore.setLaunchAtLoginEnabled($0) }
        )
    }

    private var launchAtLoginStatusMessage: String? {
        switch settingsStore.launchAtLoginStatus {
        case .enabled, .notRegistered, .notFound:
            // `.notFound` is what `SMAppService.mainApp.status` reports before the
            // app has ever been registered — indistinguishable from `.notRegistered`
            // from the user's perspective, not a real unavailability signal.
            nil
        case .requiresApproval:
            "Waiting for approval in System Settings > Login Items."
        case let .failed(message):
            message
        }
    }
}

private struct MenuBarSettingsRow: Identifiable {
    let kind: MetricKind
    let title: String

    var id: MetricKind { kind }

    static let allRows: [MenuBarSettingsRow] = [
        MenuBarSettingsRow(kind: .cpu, title: "CPU"),
        MenuBarSettingsRow(kind: .memory, title: "Memory"),
        MenuBarSettingsRow(kind: .temperature, title: "Temperature"),
        MenuBarSettingsRow(kind: .network, title: "Network"),
        MenuBarSettingsRow(kind: .storage, title: "Storage"),
        MenuBarSettingsRow(kind: .battery, title: "Battery"),
        MenuBarSettingsRow(kind: .gpu, title: "GPU")
    ]
}

private extension RefreshRate {
    var displayName: String {
        switch self {
        case .oneSecond: "1 second"
        case .twoSeconds: "2 seconds"
        case .fiveSeconds: "5 seconds"
        }
    }
}

private extension ByteUnitSystem {
    var displayName: String {
        switch self {
        case .decimal: "GB (decimal)"
        case .binary: "GiB (binary)"
        }
    }
}

private extension TemperatureUnit {
    var displayName: String {
        switch self {
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }
}

#Preview {
    SettingsView(settingsStore: SettingsStore(defaults: UserDefaults(suiteName: "preview.settings") ?? .standard))
}

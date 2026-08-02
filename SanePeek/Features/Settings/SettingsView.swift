//
//  SettingsView.swift
//  SanePeek
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings will be available in a later phase.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .navigationTitle("Settings")
        .accessibilityIdentifier("settings.root")
    }
}

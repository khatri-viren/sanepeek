import Foundation

nonisolated enum MenuBarDisplayMode: String, Codable, CaseIterable, Equatable, Sendable {
    case number
    case bar

    var displayName: String {
        switch self {
        case .number: "Number"
        case .bar: "Bar"
        }
    }
}

/// Per-metric menu bar preference: whether it shows a `MenuBarExtra` item at all, and in
/// which form. Keyed by `MetricKind` in `SettingsStore.menuBarConfig`.
nonisolated struct MenuBarMetricConfig: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var displayMode: MenuBarDisplayMode
}

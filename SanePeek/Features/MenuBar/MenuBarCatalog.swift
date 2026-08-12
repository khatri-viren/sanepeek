/// Semantic metadata shared by the menu bar's AppKit, SwiftUI, and settings adapters.
///
/// The adapters intentionally retain separate orders because status items use a compact order
/// while the popup and settings follow the monitoring grouping. This module centralizes
/// the metric metadata without owning live state, AppKit objects, or SwiftUI layout.
nonisolated struct MenuBarMetricDescriptor: Identifiable, Hashable, Sendable {
    let kind: MetricKind
    let settingsTitle: String
    let abbreviation: String

    var id: MetricKind { kind }
}

nonisolated enum MenuBarCatalog {
    /// The complete semantic catalog. Every `MetricKind` must have exactly one entry here.
    static let metrics: [MenuBarMetricDescriptor] = [
        MenuBarMetricDescriptor(kind: .cpu, settingsTitle: "CPU", abbreviation: "CPU"),
        MenuBarMetricDescriptor(kind: .memory, settingsTitle: "Memory", abbreviation: "RAM"),
        MenuBarMetricDescriptor(kind: .temperature, settingsTitle: "Temperature", abbreviation: "TMP"),
        MenuBarMetricDescriptor(kind: .network, settingsTitle: "Network", abbreviation: "NET"),
        MenuBarMetricDescriptor(kind: .storage, settingsTitle: "Storage", abbreviation: "SSD"),
        MenuBarMetricDescriptor(kind: .battery, settingsTitle: "Battery", abbreviation: "BAT"),
        MenuBarMetricDescriptor(kind: .gpu, settingsTitle: "GPU", abbreviation: "GPU")
    ]

    /// Status items use the compact order selected for the menu bar itself.
    static let statusItemOrder: [MetricKind] = [
        .cpu, .memory, .storage, .network, .battery, .gpu, .temperature
    ]

    /// Popup rows follow the monitoring-oriented grouping rather than status-item declaration order.
    static let popoverOrder: [MetricKind] = [
        .cpu, .memory, .temperature, .network, .storage, .battery, .gpu
    ]

    /// Settings currently mirrors the popup, but remains a named order so it can diverge safely.
    static let settingsOrder: [MetricKind] = [
        .cpu, .memory, .temperature, .network, .storage, .battery, .gpu
    ]

    static var popoverRows: [MenuBarMetricDescriptor] {
        popoverOrder.map { descriptor(for: $0) }
    }

    static var settingsRows: [MenuBarMetricDescriptor] {
        settingsOrder.map { descriptor(for: $0) }
    }

    static func descriptor(for kind: MetricKind) -> MenuBarMetricDescriptor {
        guard let descriptor = metrics.first(where: { $0.kind == kind }) else {
            preconditionFailure("Missing menu bar descriptor for \(kind.rawValue)")
        }
        return descriptor
    }
}

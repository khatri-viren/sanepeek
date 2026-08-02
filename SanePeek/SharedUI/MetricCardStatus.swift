import SwiftUI

/// Conveyed via symbol *and* word everywhere it's shown, never color alone.
nonisolated enum MetricCardStatus: Equatable {
    case normal
    case warning
    case critical

    var tintColor: Color? {
        switch self {
        case .normal: nil
        case .warning: MetricPalette.warning
        case .critical: MetricPalette.critical
        }
    }

    var symbolName: String? {
        switch self {
        case .normal: nil
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    var accessibilityWord: String? {
        switch self {
        case .normal: nil
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

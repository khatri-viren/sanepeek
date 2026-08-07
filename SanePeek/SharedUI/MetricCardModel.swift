import SwiftUI

/// Presentation-ready state for one dashboard card. Built by `MetricCardMapping`
/// from a domain snapshot; `MetricCardView` only ever renders this, never a snapshot.
nonisolated struct MetricCardModel: Identifiable, Equatable {
    let id: MetricKind
    let title: String
    let systemImage: String
    let accentColor: Color
    let primaryValue: String
    let secondaryValue: String?
    let status: MetricCardStatus?
    let unavailableMessage: String?
    /// Trailing sparkline samples; empty when this card has no history-backed chart.
    let sparklineValues: [Double]
    /// 0...1 fill level for the menu bar item's battery-style bar, or nil when the
    /// metric has no reading yet. Every metric provides one — unlike `sparklineValues`,
    /// which storage and battery leave empty — since the bar is a "how full is it right
    /// now" gauge, not a trend, and an item that renders nothing is worse than a flat one.
    /// See `MetricCardMapping` for what each metric fills against.
    let levelFraction: Double?
    /// 0...1 usage fraction for the storage ring; nil for every other card.
    let usageFraction: Double?
    let accessibilityLabel: String
    let accessibilityValue: String
}

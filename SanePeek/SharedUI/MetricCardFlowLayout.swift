import SwiftUI

private nonisolated struct MetricCardSpanKey: LayoutValueKey {
    static let defaultValue: Int = 1
}

extension View {
    /// Asks `MetricCardFlowLayout` to give this card `span` columns instead of
    /// one. Clamped to the column count actually available, so a 2-column card
    /// still lays out correctly in a window only wide enough for one.
    func metricCardSpan(_ span: Int) -> some View {
        layoutValue(key: MetricCardSpanKey.self, value: span)
    }
}

/// Reflowing card grid: fits as many `minCardWidth` columns as the proposed
/// width allows, divides the width evenly between them (never exceeding
/// `maxCardWidth`), and wraps cards onto as many rows as needed. Cards may
/// claim several columns via `metricCardSpan(_:)`.
///
/// Neither stock container does both halves of this job: `LazyVGrid(.adaptive)`
/// reflows but has no column span, while `Grid` has `gridCellColumns` but a
/// fixed column count that squeezes every cell thinner instead of dropping a
/// column as the window narrows.
///
/// Being a `Layout` rather than a `GeometryReader` plus `@State` width matters:
/// the proposed width arrives during the layout pass, so cards are correctly
/// sized on the very first frame. Measuring into state instead needs a second
/// pass, and until it lands every card is framed at zero width — invisible both
/// on screen and to accessibility queries.
nonisolated struct MetricCardFlowLayout: Layout {
    /// Mirrors the `.adaptive(minimum: 260, maximum: 380)` sizing the dashboard
    /// used before the CPU card needed a column span.
    var minCardWidth: CGFloat = 260
    var maxCardWidth: CGFloat = 380
    var spacing: CGFloat = MetricSpacing.gridSpacing

    struct Row {
        var placements: [(index: Int, width: CGFloat)] = []
        var height: CGFloat = 0
    }

    /// `sizeThatFits` and `placeSubviews` run back-to-back in the same layout pass with the same
    /// resolved width, so without a cache every subview's `sizeThatFits(_:)` — the expensive part
    /// for chart-bearing cards — ran twice per pass. Caching the last computed rows against the
    /// width they were computed for cuts that in half; `updateCache` resets it whenever the
    /// subview set itself changes (a card appearing/disappearing), so a stale row layout is never
    /// reused (performance review P8).
    struct Cache {
        var rows: [Row] = []
        var width: CGFloat = -1
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = resolvedWidth(from: proposal)
        let rows = rows(for: subviews, availableWidth: width, cache: &cache)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let width = bounds.width > 0 ? bounds.width : resolvedWidth(from: proposal)
        var y = bounds.minY

        for row in rows(for: subviews, availableWidth: width, cache: &cache) {
            var x = bounds.minX
            for placement in row.placements {
                subviews[placement.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    // Row height, not the card's own: cards that stretch (the
                    // unavailable state's spacers) then match their neighbours
                    // instead of leaving ragged gaps in the row.
                    proposal: ProposedViewSize(width: placement.width, height: row.height)
                )
                x += placement.width + spacing
            }
            y += row.height + spacing
        }
    }

    /// A nil or infinite width proposal (an ideal-size query rather than a real
    /// layout pass) resolves to a single full-size column rather than zero, so
    /// cards report a usable intrinsic size instead of collapsing.
    private func resolvedWidth(from proposal: ProposedViewSize) -> CGFloat {
        guard let width = proposal.width, width.isFinite, width > 0 else { return maxCardWidth }
        return width
    }

    private func rows(for subviews: Subviews, availableWidth: CGFloat, cache: inout Cache) -> [Row] {
        if cache.width == availableWidth, !cache.rows.isEmpty {
            return cache.rows
        }

        let computed = computeRows(for: subviews, availableWidth: availableWidth)
        cache.rows = computed
        cache.width = availableWidth
        return computed
    }

    private func computeRows(for subviews: Subviews, availableWidth: CGFloat) -> [Row] {
        let columns = max(1, Int((availableWidth + spacing) / (minCardWidth + spacing)))
        let columnWidth = max(
            0,
            min(maxCardWidth, (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        )

        var rows: [Row] = []
        var current = Row()
        var usedColumns = 0

        for index in subviews.indices {
            let span = min(max(1, subviews[index][MetricCardSpanKey.self]), columns)

            if usedColumns > 0, usedColumns + span > columns {
                rows.append(current)
                current = Row()
                usedColumns = 0
            }

            let width = columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height

            current.placements.append((index: index, width: width))
            current.height = max(current.height, height)
            usedColumns += span
        }

        if !current.placements.isEmpty {
            rows.append(current)
        }

        return rows
    }
}

import AppKit
import SwiftUI

/// A menu bar item's content in either display mode: the metric's three-letter name stacked one
/// letter per line, followed by its current value or its level bar.
///
/// Both modes are drawn through `MenuBarLabelImage` before assignment to an AppKit status
/// button. One composed image keeps the stacked name and value/bar aligned as a single unit.
struct MenuBarLabelContent: View {
    let kind: MetricKind
    let displayMode: MenuBarDisplayMode
    let value: String
    let fraction: Double?

    private static let spacing: CGFloat = 1
    /// Keep the rendered status-item width independent of the current number of digits. The
    /// shared popover is anchored to the status button's bounds, so letting a live value resize
    /// this column makes its arrow walk left and right as values cross a digit boundary. Wider
    /// formats get their own stable width so units such as "°C" stay on the same line.
    private static func numberValueWidth(for kind: MetricKind) -> CGFloat {
        switch kind {
        case .cpu, .memory, .gpu, .battery:
            30
        case .temperature:
            56
        case .storage:
            64
        case .network:
            76
        }
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            MenuBarMetricAbbreviation(kind: kind)

            switch displayMode {
            case .number:
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    // Keep the fixed column's empty space on the trailing side. That preserves
                    // stable popover anchoring without inserting a visible gap after the label.
                    .frame(width: Self.numberValueWidth(for: kind), alignment: .leading)
            case .bar:
                MenuBarLevelBar(fraction: fraction)
            }
        }
    }
}

/// The metric's three-letter name, stacked one letter per line.
///
/// Shown in both display modes. Three lines share roughly the height one line of `.number`
/// mode's 12pt text takes, so the type is necessarily tiny — chosen over a horizontal label to
/// keep each menu bar item narrow.
struct MenuBarMetricAbbreviation: View {
    let kind: MetricKind

    private static let fontSize: CGFloat = 6
    /// Pinned per line rather than left to the font's natural line height, which stacks three
    /// lines ~22pt tall — past what a menu bar item can show. Uppercase has no descenders and a
    /// cap height near 4pt at this size, so a 6.5pt line box crops nothing.
    private static let lineHeight: CGFloat = 6.5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(kind.menuBarAbbreviation.enumerated()), id: \.offset) { _, letter in
                Text(String(letter))
                    .font(.system(size: Self.fontSize, weight: .bold, design: .rounded))
                    .frame(height: Self.lineHeight)
            }
        }
    }
}

extension MetricKind {
    /// Exactly three letters for every metric, so the stacked labels are all the same height
    /// and the bars beside them stay aligned across items.
    ///
    /// `RAM`/`SSD` rather than `MEM`/`DSK` by user choice — they read more naturally on a Mac.
    /// `TMP` is the one genuinely arbitrary pick; temperature has no conventional shorthand.
    var menuBarAbbreviation: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "RAM"
        case .gpu: "GPU"
        case .network: "NET"
        case .storage: "SSD"
        case .battery: "BAT"
        case .temperature: "TMP"
        }
    }
}

/// Draws `MenuBarLabelContent` by rasterizing it into a template image.
///
/// Each AppKit status button receives a single `NSImage`. `ImageRenderer` draws the complete
/// stacked abbreviation and custom level bar before it reaches the status bar, so that compact
/// layout stays stable regardless of the button's native rendering behavior.
///
/// **Template rendering is conditional on there being no status tint.** A template image keeps
/// only alpha, which is exactly right at normal status: the system paints it in the menu bar's
/// own foreground, so it follows light/dark and the menu-bar-tinting accessibility setting for
/// free. But it also means a template image cannot carry orange or red. So a warning/critical
/// tint is baked into the pixels instead and `isTemplate` left off — the appearance is frozen
/// at render time, which is fine precisely because the color is the point.
///
/// This is called on metrics updates, but its per-metric cache skips rasterization whenever the
/// displayed pixels have not changed.
struct MenuBarLabelImage: View {
    let kind: MetricKind
    let displayMode: MenuBarDisplayMode
    let value: String
    let fraction: Double?
    /// The warning/critical color, or nil at normal status — which is also the switch between
    /// a template image and a color one.
    let tint: Color?

    var body: some View {
        if let image = Self.renderedImage(
            kind: kind,
            displayMode: displayMode,
            value: value,
            fraction: fraction,
            tint: tint
        ) {
            Image(nsImage: image)
        } else {
            // Falling back to the plain value text keeps the item readable if rasterization
            // ever fails; a `Shape` fallback would be the very thing that doesn't draw.
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(tint ?? .primary)
        }
    }

    /// Keyed by `kind` rather than a single slot: every enabled metric renders its own item
    /// concurrently, and each has its own independent "did the pixels actually change" answer.
    @MainActor
    private static var renderCache: [MetricKind: (key: RenderCacheKey, image: NSImage)] = [:]

    private struct RenderCacheKey: Equatable {
        let displayMode: MenuBarDisplayMode
        let value: String
        let fraction: Double?
        let tint: Color?
        let scale: CGFloat
    }

    /// Rasterizing through `ImageRenderer` costs real time — it's a full mini SwiftUI render
    /// pass, not a cheap draw call — and storage/battery/temperature only change once every 30s,
    /// so most ticks re-rasterize pixels identical to last time. Skipping that when nothing this
    /// image depends on has changed is a straight win with no visual cost (performance
    /// review P7).
    @MainActor
    static func renderedImage(
        kind: MetricKind,
        displayMode: MenuBarDisplayMode,
        value: String,
        fraction: Double?,
        tint: Color?
    ) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let key = RenderCacheKey(
            displayMode: displayMode,
            value: value,
            fraction: fraction,
            tint: tint,
            scale: scale
        )
        if let cached = renderCache[kind], cached.key == key {
            return cached.image
        }

        let content = MenuBarLabelContent(
            kind: kind,
            displayMode: displayMode,
            value: value,
            fraction: fraction
        )
        // At normal status the content draws in `.primary` and the system recolors the whole
        // template for the menu bar; a tint has to be applied here, before rasterizing, since
        // nothing downstream can add color back to a flattened image.
        let renderer = ImageRenderer(content: content.foregroundStyle(tint ?? .primary))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = tint == nil
        renderCache[kind] = (key, image)
        return image
    }
}

/// A single battery-style level bar: a rounded outline that fills in proportion to the metric's
/// current reading, the way macOS's own battery item reads at a glance.
///
/// Stood upright and filling bottom-to-top, per the user's choice — the battery glyph it
/// borrows from is horizontal, but a vertical bar reads as a level meter rather than as a
/// second battery sitting next to the real one.
///
/// Replaces a miniature 16-sample Swift Charts bar chart that was too dense to read at status
/// bar scale. It is rendered into the status button's composed label image.
///
/// A level bar rather than a smaller chart, for two independent reasons. A menu bar item is too
/// narrow to carry a trend: the old chart's bars were `.fixed(2)` wide, so 16 of them needed
/// 32pt inside a 28pt frame and overlapped into one solid mass (measured by rendering that
/// chart to a bitmap — 3 samples paint 9% of the frame and read as bars, 16 paint 58% and read
/// as a slab). And a level works for storage and battery, whose `sparklineValues` are empty, so
/// every metric can offer bar mode rather than only the history-backed ones.
///
/// The unfilled part of the bar stays genuinely unpainted rather than tinted a faint color,
/// because the rasterized result is a template image where alpha is the only surviving channel
/// — a filled-in "empty" half would collapse to the same silhouette as a full bar.
struct MenuBarLevelBar: View {
    /// 0...1, or nil when the metric has no reading yet — drawn as an empty outline, so the
    /// item still occupies its slot instead of vanishing from the menu bar.
    let fraction: Double?

    /// 16pt tall sits just under the ~18pt the system's own menu bar glyphs occupy inside a
    /// 24pt item, and the 1:2 ratio is the battery glyph's proportion turned on its side.
    /// Narrower than 8pt and the 4pt-wide fill inside it stops reading as a bar at all.
    static let width: CGFloat = 8
    static let height: CGFloat = 16
    private static let borderWidth: CGFloat = 1
    /// Gap between the outline and the fill, so the two never visually merge into one slab.
    private static let fillInset: CGFloat = 2
    /// Any non-zero reading still paints at least this much, or a low single-digit percentage
    /// would round to a sub-pixel sliver and read as an empty bar.
    private static let minimumFillHeight: CGFloat = 2
    /// Deliberately short of a `Capsule`'s half-width (4pt here), which domed both ends and
    /// turned a low reading into a floating dot rather than a bar sitting on the bottom.
    private static let cornerRadius: CGFloat = 2.5
    /// Tracks the outline's arc one border-width in, so the two stay concentric instead of the
    /// fill looking squarer than the shape holding it.
    private static let fillCornerRadius: CGFloat = 1.5

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                // Dimmer than the fill so the container reads as chrome rather than as data —
                // alpha is the one channel that survives template rendering.
                .strokeBorder(.primary.opacity(0.4), lineWidth: Self.borderWidth)

            RoundedRectangle(cornerRadius: Self.fillCornerRadius, style: .continuous)
                .fill(.primary)
                .frame(width: Self.width - Self.fillInset * 2, height: fillHeight)
                .padding(.bottom, Self.fillInset)
        }
        .frame(width: Self.width, height: Self.height)
    }

    private var fillHeight: CGFloat {
        guard let fraction, fraction > 0 else { return 0 }
        let trackHeight = Self.height - Self.fillInset * 2
        return max(Self.minimumFillHeight, trackHeight * min(fraction, 1))
    }
}

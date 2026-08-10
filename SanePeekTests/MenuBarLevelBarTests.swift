import AppKit
import SwiftUI
import Testing

@testable import SanePeek

/// Renders `MenuBarLevelBar` to pixels and counts what it actually painted.
///
/// The bug this replaced was precisely "the menu bar item draws nothing", which every assertion
/// about the *model* passes through happily. So these tests assert on the drawing, not on the
/// inputs to it: that a reading paints something, that more of it paints more, and that the bar
/// leaves real transparency around itself — `MenuBarLevelBarImage` rasterizes this view into a
/// *template* image, where alpha is the only surviving channel, so anything that painted a
/// background would collapse a full bar and an empty one into the same silhouette.
///
/// These cover the drawing only. The final status-bar composition still needs a live menu-bar
/// check, because the tests render an image rather than exercise an `NSStatusBarButton`.
@MainActor
@Suite("MenuBarLevelBar rendering")
struct MenuBarLevelBarTests {
    /// Below the outline's own alpha, so the outline counts as painted, but high enough to
    /// ignore fully-transparent background pixels.
    private static let paintedAlphaThreshold: CGFloat = 0.1

    @Test("Every reading paints visible pixels rather than an empty frame")
    func drawsSomethingForEveryReading() {
        for fraction in [0.05, 0.25, 0.5, 0.75, 1.0] {
            #expect(paintedPixelCount(fraction: fraction) > 0, "nothing drawn at \(fraction)")
        }
    }

    @Test("A higher reading paints a longer bar")
    func fillGrowsWithTheReading() {
        let quarter = paintedPixelCount(fraction: 0.25)
        let half = paintedPixelCount(fraction: 0.5)
        let full = paintedPixelCount(fraction: 1)

        #expect(quarter < half)
        #expect(half < full)
    }

    /// Both draw the outline and nothing else, so they render identically — an unavailable
    /// metric reads as an empty bar, not as a missing menu bar item.
    @Test("An empty and an absent reading both draw the outline alone")
    func emptyAndUnavailableDrawOnlyTheOutline() {
        let empty = paintedPixelCount(fraction: 0)
        let unavailable = paintedPixelCount(fraction: nil)

        #expect(empty > 0)
        #expect(empty == unavailable)
        #expect(empty < paintedPixelCount(fraction: 1))
    }

    /// A reading past 1 (network's self-scaled level can't produce one, but nothing in the type
    /// prevents it) must pin the bar full rather than overflow the capsule.
    @Test("An over-full reading is clamped to a full bar")
    func overfullReadingClampsToFull() {
        #expect(paintedPixelCount(fraction: 2) == paintedPixelCount(fraction: 1))
    }

    /// The corners sit outside the capsule, so a bar that paints its own background — the old
    /// chart's failure mode — would fill them in and render every fraction as one silhouette.
    @Test("Even a full bar leaves its corners transparent")
    func fullBarIsNotASolidRectangle() {
        guard let bitmap = render(fraction: 1) else {
            Issue.record("could not render MenuBarLevelBar")
            return
        }

        let corners = [
            (0, 0),
            (bitmap.pixelsWide - 1, 0),
            (0, bitmap.pixelsHigh - 1),
            (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)
        ]
        for (x, y) in corners {
            let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
            #expect(alpha < Self.paintedAlphaThreshold, "corner (\(x), \(y)) was painted")
        }
    }

    private func render(fraction: Double?) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: MenuBarLevelBar(fraction: fraction))
        renderer.scale = 2
        guard let data = renderer.nsImage?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: data)
    }

    private func paintedPixelCount(fraction: Double?) -> Int {
        guard let bitmap = render(fraction: fraction) else {
            Issue.record("could not render MenuBarLevelBar at \(String(describing: fraction))")
            return 0
        }

        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > Self.paintedAlphaThreshold {
                count += 1
            }
        }
        return count
    }
}

/// Covers the three-letter names stacked beside each bar, and the composition of the two.
///
/// Same limitation as `MenuBarLevelBarTests`: these prove the content draws under
/// `ImageRenderer`, which is how `MenuBarLabelImage` produces it. Anything about the final menu
/// bar layout still needs a live status-item check.
@MainActor
@Suite("Menu bar metric abbreviations")
struct MenuBarMetricAbbreviationTests {
    /// Equal-length names are what keep the bars vertically aligned across items — a 2- or
    /// 4-letter outlier would shift its own bar and break the row.
    @Test("Every metric has a distinct three-letter uppercase name")
    func abbreviationsAreThreeUppercaseLettersAndUnique() {
        let abbreviations = MetricKind.allCases.map(\.menuBarAbbreviation)

        for (kind, abbreviation) in zip(MetricKind.allCases, abbreviations) {
            #expect(abbreviation.count == 3, "\(kind) is \"\(abbreviation)\"")
            #expect(
                abbreviation.allSatisfy { $0.isUppercase && $0.isLetter },
                "\(kind) is \"\(abbreviation)\""
            )
        }

        #expect(Set(abbreviations).count == MetricKind.allCases.count)
    }

    /// The bug this guards: the name silently contributing nothing, leaving a bare bar.
    @Test("The label paints more than the bar alone, for every metric")
    func labelPaintsTheNameAlongsideTheBar() {
        let barOnly = paintedPixelCount(MenuBarLevelBar(fraction: 0.5))

        for kind in MetricKind.allCases {
            let withName = paintedPixelCount(
                MenuBarLabelContent(kind: kind, displayMode: .bar, value: "50%", fraction: 0.5)
            )
            #expect(withName > barOnly, "\(kind) drew nothing beyond its bar")
        }
    }

    /// The same name has to appear in `.number` mode, which was added after bar mode and shares
    /// the identical rasterization path.
    @Test("Number mode paints more than its value text alone, for every metric")
    func numberModePaintsTheNameAlongsideTheValue() {
        for kind in MetricKind.allCases {
            let valueOnly = paintedPixelCount(
                Text("50%").font(.system(size: 12, weight: .medium, design: .rounded))
            )
            let withName = paintedPixelCount(
                MenuBarLabelContent(kind: kind, displayMode: .number, value: "50%", fraction: nil)
            )
            #expect(withName > valueOnly, "\(kind) drew nothing beyond its value")
        }
    }

    /// Three letters stacked have to stay inside what a menu bar item can show. The bar is
    /// 16pt, and the label may not tower over it.
    @Test("The stacked name stays close to the bar's own height")
    func stackedNameFitsAMenuBarItem() {
        for displayMode in MenuBarDisplayMode.allCases {
            let content = MenuBarLabelContent(
                kind: .cpu,
                displayMode: displayMode,
                value: "100%",
                fraction: 0.5
            )
            guard let image = ImageRenderer(content: content).nsImage else {
                Issue.record("could not render MenuBarLabelContent in \(displayMode)")
                return
            }

            #expect(image.size.height <= 20, "\(displayMode) is \(image.size.height)pt tall")
        }
    }

    private func paintedPixelCount(_ content: some View) -> Int {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let data = renderer.nsImage?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data)
        else {
            Issue.record("could not render content")
            return 0
        }

        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                count += 1
            }
        }
        return count
    }
}

@MainActor
@Suite("Menu bar metric label layout")
struct MenuBarMetricLabelLayoutTests {
    @Test("Number labels keep the same width as values gain digits")
    func numberLabelsKeepStableWidthAcrossDigitChanges() {
        let widths = ["1%", "10%", "100%"].compactMap { value in
            ImageRenderer(
                content: MenuBarLabelContent(
                    kind: .cpu,
                    displayMode: .number,
                    value: value,
                    fraction: nil
                )
            ).nsImage?.size.width
        }

        #expect(widths.count == 3)
        #expect(Set(widths).count == 1, "Rendered widths changed across digit counts: \(widths)")
    }

    @Test("Temperature labels stay on one line")
    func temperatureLabelsDoNotWrap() {
        for value in ["68.6 °C", "105.0 °C"] {
            let image = ImageRenderer(
                content: MenuBarLabelContent(
                    kind: .temperature,
                    displayMode: .number,
                    value: value,
                    fraction: nil
                )
            ).nsImage

            guard let image else {
                Issue.record("Could not render the temperature menu-bar label")
                return
            }
            #expect(image.size.height <= 20, "Temperature label wrapped to \(image.size.height)pt for \(value)")
        }
    }
}

/// Covers how warning/critical status reaches the menu bar, which is now **color alone** — the
/// status symbol badge that used to sit beside the item was removed as clutter, so if the color
/// fails to survive rasterization there is no other signal that a threshold was crossed.
///
/// The trap this guards is specific: a template `NSImage` keeps only alpha, so setting
/// `isTemplate` unconditionally would silently discard orange and red and render every state
/// identically. Normal status *must* stay template so the system can adapt it to light/dark and
/// to the menu-bar-tinting accessibility setting.
@MainActor
@Suite("Menu bar status tinting")
struct MenuBarStatusTintTests {
    @Test("Normal status renders a template image, a status tint renders a color one")
    func templateOnlyWhenThereIsNoTint() {
        #expect(image(tint: nil)?.isTemplate == true)
        #expect(image(tint: MetricCardStatus.warning.tintColor)?.isTemplate == false)
        #expect(image(tint: MetricCardStatus.critical.tintColor)?.isTemplate == false)
    }

    /// `isTemplate` alone doesn't prove the color was ever applied — this checks the pixels.
    @Test("A tinted render actually paints color, an untinted one stays grayscale")
    func tintReachesThePixels() {
        #expect(isGrayscale(image(tint: nil)))
        #expect(!isGrayscale(image(tint: MetricCardStatus.warning.tintColor)))
        #expect(!isGrayscale(image(tint: MetricCardStatus.critical.tintColor)))
    }

    @Test("Warning and critical are told apart by their pixels, not just by both being colored")
    func warningAndCriticalDiffer() {
        let warning = image(tint: MetricCardStatus.warning.tintColor)?.tiffRepresentation
        let critical = image(tint: MetricCardStatus.critical.tintColor)?.tiffRepresentation

        #expect(warning != nil)
        #expect(warning != critical)
    }

    private func image(tint: Color?) -> NSImage? {
        MenuBarLabelImage.renderedImage(
            kind: .cpu,
            displayMode: .bar,
            value: "97%",
            fraction: 0.97,
            tint: tint
        )
    }

    /// True when every painted pixel has equal RGB components — what `.primary` produces, and
    /// what a lost tint would collapse to.
    private func isGrayscale(_ image: NSImage?) -> Bool {
        guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
            Issue.record("could not render MenuBarLabelImage")
            return false
        }

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 else { continue }
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                if let low = channels.min(), let high = channels.max(), high - low > 0.05 {
                    return false
                }
            }
        }
        return true
    }
}

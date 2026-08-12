import AppKit
import SwiftUI

/// Forces the hosting `NSWindow`'s appearance for presentation surfaces SwiftUI's
/// `.preferredColorScheme` cannot reach. The shared AppKit monitor window needs this so its panel and
/// SwiftUI foreground colors agree with the user's preference.
///
/// Unlike `WindowAccessor` this reapplies in `updateNSView`, so flipping the setting restyles a
/// popup that already exists rather than only ones opened afterwards.
struct WindowAppearanceAccessor: NSViewRepresentable {
    let colorScheme: ColorScheme?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            apply(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        // `nil` means "follow the system", which is what a nil `appearance` already does.
        view.window?.appearance = appearanceName.map(NSAppearance.init(named:)) ?? nil
    }

    private var appearanceName: NSAppearance.Name? {
        switch colorScheme {
        case .dark: .darkAqua
        case .light: .aqua
        default: nil
        }
    }
}

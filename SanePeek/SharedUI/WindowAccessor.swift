import AppKit
import SwiftUI

/// Bridges to the `NSWindow` hosting a SwiftUI view — SwiftUI has no direct API to read, let
/// alone observe the close of, the window a given view lives in. `DashboardView` uses this to
/// tell `DockIconController` exactly when its own window opens/closes (V1.1 plan 3d), rather
/// than the controller guessing at other windows by title or identifier.
///
/// The window isn't available yet in `makeNSView` (the view isn't attached to a window at
/// creation time), so resolution is deferred to the next run loop turn, by which point AppKit
/// has attached the backing `NSView` to its `NSWindow`.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Forces the hosting `NSWindow`'s appearance, for the windows `.preferredColorScheme` can't
/// reach. `MenuBarExtra(.window)` is one: its content honours no color scheme preference, so
/// the popups stayed light whatever the user picked in Settings. Setting `NSWindow.appearance`
/// works because it drives `effectiveAppearance`, which selects both the variant of the root
/// Liquid Glass the system draws behind the popup and the color scheme SwiftUI resolves
/// `.primary`/`.secondary` against — so the panel and its text stay in step.
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

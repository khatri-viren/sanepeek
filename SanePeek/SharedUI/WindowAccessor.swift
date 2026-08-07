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

import AppKit

/// `Info.plist`'s `LSUIElement = YES` already keeps the app backgrounded (no dock icon) from
/// process launch. The delegate owns the AppKit controllers that must outlive SwiftUI view
/// recreation: the dashboard dock-icon controller and the single shared menu-bar popover.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dockIconController = DockIconController()
    let menuBarPopoverController = MenuBarPopoverController()
}

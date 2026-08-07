import AppKit

/// `Info.plist`'s `LSUIElement = YES` already keeps the app backgrounded (no dock icon) from
/// process launch, so this delegate has nothing to do at launch itself — it exists to own the
/// `DockIconController` instance shared between `SanePeekApp` and `DashboardView` (V1.1 plan 3d).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dockIconController = DockIconController()
}

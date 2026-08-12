import AppKit

/// `Info.plist`'s `LSUIElement = YES` keeps the app backgrounded (with no Dock icon) from
/// process launch. The delegate is the composition root for the agent app: it owns the one
/// application-wide state object and installs the shared menu-bar popover directly at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    let menuBarPopoverController = MenuBarPopoverController()

    override init() {
        appState = AppState(dependencies: .forLaunch())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarPopoverController.configure(appState: appState)
    }
}

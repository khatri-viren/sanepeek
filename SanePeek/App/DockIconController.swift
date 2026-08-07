import AppKit

/// Owns the "no dock icon by default, one appears only while the dashboard window is open"
/// behavior (V1.1 plan 3d). The app stays fully backgrounded from process launch via
/// `Info.plist`'s `LSUIElement = YES` — a throwaway spike confirmed that relying on
/// `applicationDidFinishLaunching` to call `setActivationPolicy(.accessory)` instead left a
/// real, visible ~600ms dock-icon flash before the delegate callback ran, since the default
/// policy is `.regular` from the moment the process launches, before any app code runs.
///
/// `DashboardView` resolves its own `NSWindow` (via `WindowAccessor`) and registers it here —
/// but registration itself must not promote the dock icon: `WindowGroup` silently pre-creates
/// its window at launch (confirmed empirically — it carries real frame geometry from
/// `.defaultSize` despite never being shown), so `WindowAccessor` resolves it once at every
/// launch, whether or not the user ever opens the dashboard. Promoting there would show a dock
/// icon on every launch, defeating 3d entirely. Instead, registration only *arms* the window:
/// the policy promotes once the window is actually shown and focused (checked immediately via
/// `isKeyWindow`, not only via `didBecomeKeyNotification` — `WindowAccessor` resolves the window
/// one run loop turn after it's created, and a freshly opened window from the popup's "Open
/// Dashboard" button can already be key by then, which would otherwise mean the observer attaches
/// too late and misses the one notification it needed) and demotes again on
/// `willCloseNotification`, precise to that specific window closing rather than guessing at
/// other windows by title or identifier.
@MainActor
final class DockIconController {
    private var promotedWindowIDs: Set<ObjectIdentifier> = []
    private var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    func registerDashboardWindow(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard observers[id] == nil else { return }

        let becomeKey = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.promote(id: id) }
        }
        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.demote(id: id) }
        }
        // `queue: .main` guarantees both closures run on the main thread; `assumeIsolated`
        // tells the compiler what the runtime already guarantees, since a `@Sendable` closure
        // passed to `addObserver` isn't statically known to be MainActor-isolated.
        observers[id] = [becomeKey, willClose]

        if window.isKeyWindow {
            promote(id: id)
        }
    }

    private func promote(id: ObjectIdentifier) {
        guard !promotedWindowIDs.contains(id) else { return }
        promotedWindowIDs.insert(id)
        NSApp.setActivationPolicy(.regular)
    }

    private func demote(id: ObjectIdentifier) {
        promotedWindowIDs.remove(id)
        if let windowObservers = observers.removeValue(forKey: id) {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
        }
        if promotedWindowIDs.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

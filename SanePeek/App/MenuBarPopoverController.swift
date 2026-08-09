import AppKit
import Observation
import SwiftUI

/// Serializes status-item clicks through one popover. `MenuBarExtra(.window)` creates one
/// system-managed window per metric, which lets rapid clicks race at the Control Center scene
/// layer. Keeping one popover means a click always either presents immediately or becomes the
/// next pending presentation after the current one closes.
nonisolated enum MenuBarPopoverAction: Equatable {
    case present(MetricKind)
    case dismiss
    case none
}

nonisolated struct MenuBarPopoverCoordinator {
    private(set) var activeKind: MetricKind?
    private var pendingKind: MetricKind?
    private var isClosing = false

    mutating func select(_ kind: MetricKind, popoverIsPresented: Bool) -> MenuBarPopoverAction {
        if isClosing {
            pendingKind = kind
            return .none
        }

        guard popoverIsPresented else {
            activeKind = kind
            return .present(kind)
        }

        isClosing = true
        pendingKind = activeKind == kind ? nil : kind
        return .dismiss
    }

    mutating func popoverDidClose() -> MenuBarPopoverAction {
        isClosing = false
        activeKind = nil

        guard let pendingKind else { return .none }
        self.pendingKind = nil
        activeKind = pendingKind
        return .present(pendingKind)
    }

    mutating func cancelPresentation(for kind: MetricKind) -> Bool {
        if pendingKind == kind {
            pendingKind = nil
        }
        guard activeKind == kind else { return false }
        isClosing = true
        return true
    }
}

/// Owns the individual status items and their single shared `NSPopover`. The labels keep the
/// existing rasterized rendering path, while presentation moves out of SwiftUI scenes so AppKit
/// has exactly one popup to close and re-anchor.
@MainActor
final class MenuBarPopoverController: NSObject, NSPopoverDelegate {
    private static let displayOrder: [MetricKind] = [
        .cpu, .memory, .storage, .network, .battery, .gpu, .temperature
    ]

    private var appState: AppState?
    private var statusItems: [MetricKind: NSStatusItem] = [:]
    private var kindsByButton: [ObjectIdentifier: MetricKind] = [:]
    private var coordinator = MenuBarPopoverCoordinator()
    private let popover = NSPopover()
    private var activeSession: (kind: MetricKind, id: UInt64)?
    /// This is owned by the controller rather than read from `NSPopover.isShown`: a transient
    /// popover can start closing before the next status-button action arrives, but the delegate
    /// has not reported the close yet. Treat it as present until `popoverDidClose` so that click
    /// is queued behind the close instead of racing a second `show` call.
    private var isPopoverPresented = false

    /// The current status-item set. Kept module-internal so the AppKit ownership boundary can
    /// be regression-tested without reaching into `NSStatusBar`'s process-global state.
    var installedStatusItemKinds: Set<MetricKind> {
        Set(statusItems.keys)
    }

    /// Maps each installed item to its persistent AppKit identity. Multiple status items must
    /// use stable, unique autosave names or AppKit can restore visibility from the wrong item.
    var statusItemAutosaveNames: [MetricKind: String] {
        statusItems.mapValues(\.autosaveName)
    }

    /// Exposes the hand-off motion policy for the focused AppKit configuration test.
    var popoverAnimates: Bool {
        popover.animates
    }

    /// Short enough to still read as an instant hand-off between status items, long enough that
    /// open/close doesn't feel like a hard cut. Deliberately a manual opacity fade on the content
    /// view rather than `NSPopover.animates` — that system animation runs on its own fixed
    /// internal timing and ignores the ambient `NSAnimationContext` duration, so it can't be sped
    /// up this way. The coordinator's close-notification wait (see `popoverDidClose`) already
    /// serializes rapid clicks correctly regardless of this duration.
    private static let transitionDuration: TimeInterval = 0.05

    override init() {
        super.init()
        popover.behavior = .transient
        // The system animation ignores our duration override (see `transitionDuration`); a
        // manual fade in `presentPopover`/`closePopover` replaces it instead.
        popover.animates = false
        popover.delegate = self
    }

    func configure(appState: AppState) {
        guard self.appState !== appState else { return }

        if popover.isShown {
            popover.performClose(nil)
        }
        for statusItem in statusItems.values {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItems.removeAll()
        kindsByButton.removeAll()
        activeSession = nil
        isPopoverPresented = false
        coordinator = MenuBarPopoverCoordinator()

        self.appState = appState
        observeApplicationState()
    }

    private func observeApplicationState() {
        guard let appState else { return }

        withObservationTracking {
            syncStatusItems(for: appState)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeApplicationState()
            }
        }
    }

    private func syncStatusItems(for appState: AppState) {
        let enabledKinds = Set(Self.displayOrder.filter {
            appState.settingsStore.menuBarConfig(for: $0).isEnabled
        })

        for kind in Array(statusItems.keys) where !enabledKinds.contains(kind) {
            removeStatusItem(for: kind)
        }

        for kind in Self.displayOrder where enabledKinds.contains(kind) {
            let statusItem = statusItem(for: kind)
            update(statusItem, for: kind, appState: appState)
        }
    }

    private func statusItem(for kind: MetricKind) -> NSStatusItem {
        if let statusItem = statusItems[kind] {
            return statusItem
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // AppKit's generated autosave names are process-local (`Item-3`, `Item-4`, …). They are
        // not stable across launches, and its documentation requires explicit, unique names when
        // an app owns multiple status items. Without them, status-bar visibility can be restored
        // against the wrong metric, making Settings appear to allow only one enabled item.
        statusItem.autosaveName = "com.sanepeek.status-item.\(kind.rawValue)"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemPressed(_:))
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.sendAction(on: [.leftMouseUp])
            kindsByButton[ObjectIdentifier(button)] = kind
        }
        statusItems[kind] = statusItem
        return statusItem
    }

    private func update(_ statusItem: NSStatusItem, for kind: MetricKind, appState: AppState) {
        guard let button = statusItem.button else { return }

        let card = appState.dashboardViewModel.card(for: kind)
        let displayMode = appState.settingsStore.menuBarConfig(for: kind).displayMode
        button.image = MenuBarLabelImage.renderedImage(
            kind: kind,
            displayMode: displayMode,
            value: card?.primaryValue ?? "--",
            fraction: card?.levelFraction,
            tint: card?.status?.tintColor
        )
        let accessibilityLabel = card?.accessibilityLabel ?? "\(kind.menuBarAbbreviation), --"
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.needsDisplay = true
    }

    private func removeStatusItem(for kind: MetricKind) {
        guard let statusItem = statusItems.removeValue(forKey: kind) else { return }

        if let button = statusItem.button {
            kindsByButton.removeValue(forKey: ObjectIdentifier(button))
        }
        if coordinator.cancelPresentation(for: kind) {
            if isPopoverPresented {
                closePopover()
            } else {
                _ = coordinator.popoverDidClose()
            }
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func statusItemPressed(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton,
              let kind = kindsByButton[ObjectIdentifier(button)]
        else { return }

        perform(coordinator.select(kind, popoverIsPresented: isPopoverPresented))
    }

    private func perform(_ action: MenuBarPopoverAction) {
        switch action {
        case .present(let kind):
            presentPopover(for: kind)
        case .dismiss:
            closePopover()
        case .none:
            break
        }
    }

    private func presentPopover(for kind: MetricKind) {
        guard coordinator.activeKind == kind,
              !isPopoverPresented,
              let appState,
              let button = statusItems[kind]?.button
        else { return }

        isPopoverPresented = true
        activeSession = (kind, appState.popupDidAppear(kind: kind))
        let hostingController = NSHostingController(
            rootView: MenuBarPopoverView(appState: appState, kind: kind)
        )
        popover.contentViewController = hostingController
        button.highlight(true)

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            return
        }
        // Fade the content in ourselves rather than via `NSPopover.animates`; see
        // `transitionDuration`. The view must start invisible before `show` actually presents
        // the window, or the first frame flashes at full opacity.
        hostingController.view.alphaValue = 0
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            hostingController.view.animator().alphaValue = 1
        }
    }

    private func closePopover() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let contentView = popover.contentViewController?.view
        else {
            popover.performClose(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            contentView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.popover.performClose(nil)
        })
    }

    func popoverDidClose(_ notification: Notification) {
        isPopoverPresented = false
        if let activeSession {
            statusItems[activeSession.kind]?.button?.highlight(false)
            appState?.popupDidDisappear(kind: activeSession.kind, sessionID: activeSession.id)
            self.activeSession = nil
        }

        let nextAction = coordinator.popoverDidClose()
        guard case .present = nextAction else { return }

        // AppKit finishes tearing down the previous popover at the end of this turn. Defer the
        // next anchor so fast clicks coalesce to the newest pending item instead of reopening the
        // popup on the item that just closed.
        DispatchQueue.main.async { [weak self] in
            self?.perform(nextAction)
        }
    }
}

/// Installs the AppKit controller from the pre-created dashboard scene. Unlike a `MenuBarExtra`,
/// this bridge does not build a popup until a status item is clicked.
struct MenuBarPopoverControllerInstaller: NSViewRepresentable {
    let controller: MenuBarPopoverController
    let appState: AppState

    func makeNSView(context: Context) -> NSView {
        controller.configure(appState: appState)
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.configure(appState: appState)
    }
}

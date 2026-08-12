import AppKit
import Observation
import SwiftUI

/// Commands emitted by the status-item state machine. A direct handoff deliberately has no
/// dismiss/show phase: the shared monitor window moves first, then its SwiftUI detail changes.
nonisolated enum MenuBarPopoverAction: Equatable {
    case show(MetricKind)
    case dismiss(MetricKind)
    case handoff(from: MetricKind, to: MetricKind)
    case none
}

@MainActor
struct MenuBarRefreshCoalescer {
    private(set) var isScheduled = false

    mutating func schedule() -> Bool {
        guard !isScheduled else { return false }
        isScheduled = true
        return true
    }

    mutating func markCompleted() {
        isScheduled = false
    }
}

/// Tracks the menu-bar anchor separately from the detail selected inside the full glance view.
/// The anchor owns the pressed status-item highlight; an internal row click must not alter it.
nonisolated struct MenuBarPopoverCoordinator {
    private(set) var activeKind: MetricKind?

    mutating func select(_ kind: MetricKind, panelIsVisible: Bool) -> MenuBarPopoverAction {
        guard panelIsVisible else {
            activeKind = kind
            return .show(kind)
        }

        guard let activeKind else {
            self.activeKind = kind
            return .show(kind)
        }

        guard activeKind != kind else {
            self.activeKind = nil
            return .dismiss(kind)
        }

        self.activeKind = kind
        return .handoff(from: activeKind, to: kind)
    }

    mutating func dismiss() -> MetricKind? {
        defer { activeKind = nil }
        return activeKind
    }
}

/// Retained by the menu-bar controller for the lifetime of its cached window. Mutating this
/// observable value keeps the existing SwiftUI tree alive, which is required for chart removal
/// and insertion transitions to animate instead of appearing as a root-view replacement.
@Observable
@MainActor
final class MenuBarDetailSelection {
    var kind: MetricKind

    init(kind: MetricKind) {
        self.kind = kind
    }
}

/// A borderless `NSWindow` can still become key, so controls respond on their first click and
/// Escape reaches the responder chain. It intentionally cannot become the app's main document
/// window: this is transient monitor chrome, not a dashboard.
@MainActor
private final class MenuBarMonitorWindow: NSWindow {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Owns the individual status items and one shared monitor window. `NSPopover` cannot reanchor
/// without serializing its close and show animations; a cached window gives the metric handoff a
/// direct, deterministic path while retaining normal AppKit show/hide behavior.
@MainActor
final class MenuBarPopoverController: NSObject, NSWindowDelegate {
    private static let panelSize = NSSize(width: 560, height: 324)
    private static let panelGap: CGFloat = 3

    private var appState: AppState?
    private var statusItems: [MetricKind: NSStatusItem] = [:]
    private var kindsByButton: [ObjectIdentifier: MetricKind] = [:]
    private var coordinator = MenuBarPopoverCoordinator()
    private var monitorWindow: MenuBarMonitorWindow?
    private var hostingController: NSHostingController<MenuBarPopoverView>?
    private var detailSelection: MenuBarDetailSelection?
    private var activeSession: (kind: MetricKind, id: UInt64)?
    private var isPanelVisible = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// A click on a status item can make the monitor window resign key just before AppKit sends
    /// that button's action. Suppress that one resign callback so the action remains the source
    /// of truth for same-item toggle and direct-handoff behavior.
    private var ignoresNextResignKey = false

    /// A metrics tick updates several observed card properties independently. Queueing one
    /// observation refresh per property makes the first tick rebuild and rasterize the same
    /// status item repeatedly, which is especially expensive in an unoptimized Debug build.
    private var observationRefreshCoalescer = MenuBarRefreshCoalescer()

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

    /// Whether the shared monitor window is currently presented. The status-item action and
    /// lifecycle tests use the same selection path as AppKit without reaching into window state.
    var isMonitorWindowVisible: Bool {
        isPanelVisible
    }

    /// The detail currently represented by the shared monitor window, if it exists.
    var selectedMetricKind: MetricKind? {
        detailSelection?.kind
    }

    /// The shared window's current frame, useful for validating that a handoff keeps one window
    /// and reanchors it rather than creating a second panel.
    var monitorWindowFrame: NSRect? {
        monitorWindow?.frame
    }

    /// Applies the same selection state machine used by an AppKit status-item action. Keeping
    /// this at the controller boundary makes the shared-window behavior deterministic to test.
    @discardableResult
    func selectStatusItem(_ kind: MetricKind) -> Bool {
        guard statusItems[kind] != nil else { return false }
        perform(coordinator.select(kind, panelIsVisible: isPanelVisible))
        return true
    }

    override init() {
        super.init()
    }

    /// Releases process-global AppKit status items when the owner is no longer used. This is
    /// also useful for tests, where NSStatusBar.system survives between test cases.
    func tearDown() {
        dismissPanel()
        removeEventMonitors()
        removeLifecycleObservers()
        appState = nil
        for statusItem in statusItems.values {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItems.removeAll()
        kindsByButton.removeAll()
        monitorWindow?.orderOut(nil)
        monitorWindow = nil
        hostingController = nil
        detailSelection = nil
        activeSession = nil
        isPanelVisible = false
        coordinator = MenuBarPopoverCoordinator()
        observationRefreshCoalescer.markCompleted()
    }

    func configure(appState: AppState) {
        guard self.appState !== appState else { return }

        tearDown()
        self.appState = appState
        installLifecycleObservers()
        observeApplicationState()
    }

    private func observeApplicationState() {
        guard let appState else { return }

        withObservationTracking {
            syncStatusItems(for: appState)
        } onChange: { [weak self] in
            // Observation callbacks can arrive several times during one metrics tick. Hop to
            // the next main-queue turn so all mutations from that tick are coalesced into one
            // status-item sync instead of repeatedly rendering the same label image.
            MainActor.assumeIsolated {
                guard let self, self.observationRefreshCoalescer.schedule() else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.observationRefreshCoalescer.markCompleted()
                    self.observeApplicationState()
                }
            }
        }
    }

    private func syncStatusItems(for appState: AppState) {
        let enabledKinds = Set(MenuBarCatalog.statusItemOrder.filter {
            appState.settingsStore.menuBarConfig(for: $0).isEnabled
        })

        for kind in Array(statusItems.keys) where !enabledKinds.contains(kind) {
            removeStatusItem(for: kind)
        }

        for kind in MenuBarCatalog.statusItemOrder where enabledKinds.contains(kind) {
            let statusItem = statusItem(for: kind)
            update(statusItem, for: kind, appState: appState)
        }
    }

    private func statusItem(for kind: MetricKind) -> NSStatusItem {
        if let statusItem = statusItems[kind] {
            return statusItem
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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

        let card = appState.metricsViewModel.card(for: kind)
        let displayMode = appState.settingsStore.menuBarConfig(for: kind).displayMode
        button.image = MenuBarLabelImage.renderedImage(
            kind: kind,
            displayMode: displayMode,
            value: card?.primaryValue ?? "--",
            fraction: card?.levelFraction,
            tint: card?.status?.tintColor
        )
        let accessibilityLabel = card?.accessibilityLabel
            ?? "\(MenuBarCatalog.descriptor(for: kind).abbreviation), --"
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.needsDisplay = true
    }

    private func removeStatusItem(for kind: MetricKind) {
        if coordinator.activeKind == kind {
            dismissPanel()
        }
        guard let statusItem = statusItems.removeValue(forKey: kind) else { return }
        if let button = statusItem.button {
            kindsByButton.removeValue(forKey: ObjectIdentifier(button))
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func statusItemPressed(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton,
              let kind = kindsByButton[ObjectIdentifier(button)]
        else { return }

        perform(coordinator.select(kind, panelIsVisible: isPanelVisible))
    }

    private func perform(_ action: MenuBarPopoverAction) {
        switch action {
        case .show(let kind):
            showPanel(for: kind)
        case .dismiss(let kind):
            dismissPanel(highlightedKind: kind)
        case .handoff(let from, let to):
            handoffPanel(from: from, to: to)
        case .none:
            break
        }
    }

    private func showPanel(for kind: MetricKind) {
        guard !isPanelVisible,
              let appState,
              let button = statusItems[kind]?.button
        else { return }

        let window = makeMonitorWindow(for: appState, initialMetric: kind)
        place(window, below: button)
        activeSession = (kind, appState.popupDidAppear(kind: kind))
        button.highlight(true)
        isPanelVisible = true
        installEventMonitors()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func handoffPanel(from previousKind: MetricKind, to kind: MetricKind) {
        guard isPanelVisible,
              let window = monitorWindow,
              let button = statusItems[kind]?.button
        else { return }

        // Reposition synchronously so the content transition runs at the new anchor rather than
        // making the shell appear to slide or hop between menu-bar items.
        place(window, below: button)
        statusItems[previousKind]?.button?.highlight(false)
        button.highlight(true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        updateSelectedMetric(kind, animated: true)
    }

    private func dismissPanel() {
        guard let highlightedKind = coordinator.dismiss() else { return }
        dismissPanel(highlightedKind: highlightedKind)
    }

    private func dismissPanel(highlightedKind: MetricKind) {
        guard isPanelVisible else { return }
        isPanelVisible = false
        statusItems[highlightedKind]?.button?.highlight(false)
        monitorWindow?.orderOut(nil)
        removeEventMonitors()
        if let activeSession {
            appState?.popupDidDisappear(kind: activeSession.kind, sessionID: activeSession.id)
            self.activeSession = nil
        }
    }

    private func makeMonitorWindow(for appState: AppState, initialMetric: MetricKind) -> MenuBarMonitorWindow {
        if let monitorWindow {
            updateSelectedMetric(initialMetric, animated: false)
            return monitorWindow
        }

        let detailSelection = MenuBarDetailSelection(kind: initialMetric)

        let window = MenuBarMonitorWindow(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.animationBehavior = .default
        window.delegate = self
        window.collectionBehavior = [.moveToActiveSpace]
        window.onCancel = { [weak self] in self?.dismissPanel() }

        let rootView = MenuBarPopoverView(
            appState: appState,
            selection: detailSelection,
            onSelectedMetricChange: { [weak self] kind in self?.updateSelectedMetric(kind, animated: true) },
            onOpenSettings: { [weak self] in self?.showSettings() }
        )
        let hostingController = NSHostingController(rootView: rootView)
        window.contentView = monitorSurface(containing: hostingController.view)
        window.setContentSize(Self.panelSize)

        monitorWindow = window
        self.hostingController = hostingController
        self.detailSelection = detailSelection
        return window
    }

    /// `NSPopover` adopted the macOS liquid-glass surface automatically. A standalone window
    /// does not, so use the public AppKit glass view directly instead of approximating it with
    /// an opaque `NSVisualEffectView` material. The fallback keeps the window usable on macOS 15.
    private func monitorSurface(containing contentView: NSView) -> NSView {
        let frame = NSRect(origin: .zero, size: Self.panelSize)
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView(frame: frame)
            // `.regular` intentionally draws a pronounced glass contour. This monitor surface
            // needs to read as a light, transparent lens over the desktop instead, so use the
            // system's clear style rather than simulating transparency with a custom overlay.
            glassView.style = .clear
            glassView.cornerRadius = 24

            // `NSGlassEffectView` supplies the native blurred liquid-glass backdrop itself. Keep
            // the tint below opaque so that backdrop remains visible, while still grounding the
            // monitor in proper black/light surfaces instead of a neutral grey.
            glassView.tintColor = NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return .black.withAlphaComponent(0.65)
                }
                return .white.withAlphaComponent(0.65)
            }
            glassView.contentView = contentView
            return glassView
        }

        let materialView = NSVisualEffectView(frame: frame)
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 24
        materialView.layer?.masksToBounds = true
        materialView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: materialView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
        ])
        return materialView
    }

    private func updateSelectedMetric(_ kind: MetricKind, animated: Bool) {
        guard let detailSelection else { return }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.easeInOut(duration: 0.22)) {
                detailSelection.kind = kind
            }
        } else {
            detailSelection.kind = kind
        }

        guard var activeSession else { return }
        activeSession.kind = kind
        self.activeSession = activeSession
        appState?.popupDidSelect(kind: kind, sessionID: activeSession.id)
    }

    private func place(_ window: NSWindow, below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let buttonCenter = NSPoint(x: buttonFrame.midX, y: buttonFrame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonCenter) })
            ?? buttonWindow.screen
            ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let width = Self.panelSize.width
        let x = min(max(buttonFrame.midX - (width / 2), visibleFrame.minX), visibleFrame.maxX - width)
        let y = max(visibleFrame.minY, buttonFrame.minY - Self.panelGap - Self.panelSize.height)
        window.setFrame(NSRect(x: x, y: y, width: width, height: Self.panelSize.height), display: false, animate: false)
    }

    private func showSettings() {
        dismissPanel()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installEventMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.isPanelVisible else { return event }
            if self.isStatusItemWindow(event.window) {
                self.ignoresNextResignKey = true
                DispatchQueue.main.async { [weak self] in
                    self?.ignoresNextResignKey = false
                }
                return event
            }
            guard event.window !== self.monitorWindow else { return event }
            self.dismissPanel()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissPanel()
            }
        }
    }

    private func removeEventMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func isStatusItemWindow(_ window: NSWindow?) -> Bool {
        statusItems.values.contains { $0.button?.window === window }
    }

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let notificationCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()

        lifecycleObservers = [
            notificationCenter.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissPanel() }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissPanel() }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissPanel() }
            },
            distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissPanel() }
            }
        ]
    }

    private func removeLifecycleObservers() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        lifecycleObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        lifecycleObservers.removeAll()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !ignoresNextResignKey else { return }
        dismissPanel()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismissPanel()
        return false
    }
}

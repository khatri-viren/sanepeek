//
//  AppState.swift
//  SanePeek
//

import AppKit
import Foundation
import Observation

enum AppRuntime: String, Equatable, Sendable {
    case live
    case preview
}

/// Identifiers for `WindowGroup` scenes, shared between `SanePeekApp` (which declares them)
/// and anything that needs to `openWindow(id:)` them (the menu bar popup's "Open Dashboard").
nonisolated enum WindowID {
    static let dashboard = "dashboard"
}

/// The composition boundary for application-wide dependencies.
///
/// Keeping the boundary in place lets previews and tests avoid global
/// singletons: `.live` owns the one real `MetricsEngine` instance, `.preview`
/// carries a fixture snapshot instead.
struct AppDependencies: Sendable {
    let runtime: AppRuntime
    let fixtureSnapshot: MetricsSnapshot?
    let metricsEngine: MetricsEngine?
    let settingsDefaultsSuiteName: String?

    init(
        runtime: AppRuntime,
        fixtureSnapshot: MetricsSnapshot? = nil,
        metricsEngine: MetricsEngine? = nil,
        settingsDefaultsSuiteName: String? = nil
    ) {
        self.runtime = runtime
        self.fixtureSnapshot = fixtureSnapshot
        self.metricsEngine = metricsEngine
        self.settingsDefaultsSuiteName = settingsDefaultsSuiteName
    }

    static let live = Self(runtime: .live, metricsEngine: MetricsEngine())
    static let preview = Self(
        runtime: .preview,
        fixtureSnapshot: MetricFixtures.dashboard()
    )

    /// Builds the dashboard's tick feed for this dependency set: the live
    /// engine when one is present, otherwise a fixture feed over
    /// `fixtureSnapshot` (falling back to the baseline dashboard fixture).
    @MainActor
    func makeDashboardTickFeed() -> any DashboardTickFeed {
        if let metricsEngine {
            return LiveDashboardTickFeed(engine: metricsEngine)
        }
        return FixtureDashboardTickFeed(baseline: fixtureSnapshot ?? MetricFixtures.dashboard())
    }

    /// Builds the settings store for this dependency set, backed by
    /// `settingsDefaultsSuiteName` when UI tests need an isolated,
    /// resettable `UserDefaults` suite instead of `.standard`.
    @MainActor
    func makeSettingsStore() -> SettingsStore {
        let defaults = settingsDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        return SettingsStore(defaults: defaults)
    }

    private func withSettingsDefaultsSuiteName(_ name: String?) -> Self {
        Self(runtime: runtime, fixtureSnapshot: fixtureSnapshot, metricsEngine: metricsEngine, settingsDefaultsSuiteName: name)
    }

    /// UI tests can't rely on real hardware state (GPU support, battery
    /// presence, thresholds) being deterministic, so they launch with
    /// `-uiTestFixture <name>` to force `.preview` runtime over a specific
    /// `MetricFixtures` scenario instead of `.live`. They also pass
    /// `-uiTestSettingsSuite <name>` for an isolated, resettable settings
    /// store independent of the current fixture/runtime choice.
    static func forLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        let settingsSuiteName = value(after: "-uiTestSettingsSuite", in: arguments)

        guard let flagIndex = arguments.firstIndex(of: "-uiTestFixture"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return Self.live.withSettingsDefaultsSuiteName(settingsSuiteName)
        }

        let snapshot: MetricsSnapshot
        switch arguments[flagIndex + 1] {
        case "dashboard":
            snapshot = MetricFixtures.dashboard()
        case "warning":
            snapshot = MetricFixtures.warning()
        case "critical":
            snapshot = MetricFixtures.critical()
        case "unavailable":
            snapshot = MetricFixtures.unavailable()
        case "gpuUnsupported":
            snapshot = MetricFixtures.gpuUnsupported()
        case "mixedFailure":
            snapshot = MetricFixtures.mixedFailure()
        case "temperatureUnsupported":
            snapshot = MetricFixtures.temperatureUnsupported()
        default:
            return Self.live.withSettingsDefaultsSuiteName(settingsSuiteName)
        }

        return Self(runtime: .preview, fixtureSnapshot: snapshot, settingsDefaultsSuiteName: settingsSuiteName)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

@MainActor
@Observable
final class AppState {
    let dependencies: AppDependencies
    let settingsStore: SettingsStore
    /// The single shared ticking view model. `MetricsEngine.snapshots()` only supports one
    /// subscriber, so every consumer (dashboard, popup, and menu bar items) reads this
    /// instance instead of constructing its own.
    let dashboardViewModel: DashboardViewModel

    /// Cadence used while only menu bar items are visible (no popup/dashboard open) —
    /// deliberately slower than the user's foreground refresh-rate setting, to bound the
    /// always-on idle cost of keeping menu bar items live (V1.1 plan 3g).
    private static let backgroundCadencePolicy = CadencePolicy(refreshRate: .fiveSeconds)

    /// The menu bar item whose popup is currently open, or nil if none is. Every enabled
    /// metric has its own `MenuBarExtra`, and therefore its own popup window; observing this
    /// lets the others dismiss themselves so only one is ever on screen (see
    /// `handlePopupVisibilityChange`).
    private(set) var frontmostPopupKind: MetricKind?

    /// Exposed read-only so `DashboardView` can gate its card content on it: the window is
    /// pre-created (and its view tree kept live) at launch regardless of visibility, so without
    /// this the whole card grid — Swift Charts included — re-renders on every tick even while
    /// nobody can see it (performance review P0).
    private(set) var isDashboardVisible = false
    /// A set rather than a `Bool`: two popups overlap briefly during a hand-off, since the
    /// incoming one appears before the outgoing one has finished dismissing.
    private var visiblePopupKinds: Set<MetricKind> = []
    private var visibleDashboardWindowIDs: Set<ObjectIdentifier> = []
    private var dashboardWindowObservers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    /// The single dashboard `NSWindow`, captured the first time it resolves (at launch —
    /// `WindowGroup` pre-creates it before the user ever asks for it; see
    /// `registerDashboardWindow`). Kept so the popup's "Open Dashboard" button can re-show this
    /// exact window via AppKit instead of SwiftUI's `openWindow(id:)`, which creates a brand new
    /// `NSWindow` on every call rather than reusing one — see `presentDashboardWindow`.
    private weak var dashboardWindow: NSWindow?

    /// True while the display is asleep or the session is locked — states in which nothing the
    /// engine drives (menu bar items included; the lock screen doesn't show them) can be seen at
    /// all, so polling is paused outright rather than merely narrowed (performance review P6).
    private var isDisplayUnavailable = false
    // `nonisolated(unsafe)`, matching `DashboardViewModel.consumeTask`: only ever mutated from
    // MainActor code (`registerDisplayAvailabilityObservers`), but `deinit` is nonisolated and
    // still needs to remove these observers.
    @ObservationIgnored
    private nonisolated(unsafe) var displayAvailabilityObservers: [NSObjectProtocol] = []

    /// Held only while `recomputePollingState()` wants full coverage (popup or dashboard open).
    /// `LSUIElement` accessory apps are still subject to App Nap even while a `MenuBarExtra`
    /// popup is on screen — it doesn't register as an "actively in use" window the way a normal
    /// one does — and App Nap throttles `Task.sleep`-driven timers, which silently stretches the
    /// fast loop's real cadence past its nominal 1s interval. Since every history buffer evicts
    /// samples on wall-clock age alone, a stretched cadence permanently caps how full the chart
    /// gets rather than being a transient blip it later catches up from. This activity token is
    /// the standard opt-out: it tells the OS this process is doing user-visible work right now.
    @ObservationIgnored
    private nonisolated(unsafe) var liveViewActivity: NSObjectProtocol?

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
        let settingsStore = dependencies.makeSettingsStore()
        self.settingsStore = settingsStore
        self.dashboardViewModel = DashboardViewModel(
            feed: dependencies.makeDashboardTickFeed(),
            formatterProvider: { settingsStore.formatter }
        )

        if dependencies.metricsEngine != nil {
            settingsStore.onRefreshRateChange = { [weak self] _ in self?.recomputePollingState() }
            settingsStore.onMenuBarConfigChange = { [weak self] in self?.recomputePollingState() }
            registerDisplayAvailabilityObservers()
            recomputePollingState()
        }
    }

    deinit {
        displayAvailabilityObservers.forEach(NotificationCenter.default.removeObserver)
        displayAvailabilityObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        if let liveViewActivity {
            ProcessInfo.processInfo.endActivity(liveViewActivity)
        }
    }

    /// Screen sleep is a workspace notification; screen lock has no public API and is
    /// conventionally observed via these two well-established distributed notifications (long
    /// used by menu bar utilities for exactly this purpose, despite being unlisted in
    /// `NSWorkspace`'s API).
    private func registerDisplayAvailabilityObservers() {
        let center = NotificationCenter.default
        let distributedCenter = DistributedNotificationCenter.default()

        let sleep = center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDisplayUnavailable(true) }
        }
        let wake = center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDisplayUnavailable(false) }
        }
        let locked = distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDisplayUnavailable(true) }
        }
        let unlocked = distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDisplayUnavailable(false) }
        }
        displayAvailabilityObservers = [sleep, wake, locked, unlocked]
    }

    private func setDisplayUnavailable(_ unavailable: Bool) {
        guard isDisplayUnavailable != unavailable else { return }
        isDisplayUnavailable = unavailable
        recomputePollingState()
    }

    /// `DashboardView` calls this once its own `NSWindow` resolves (via `WindowAccessor`),
    /// rather than relying on `.onAppear`/`.onDisappear`: `WindowGroup` pre-creates its window at
    /// launch with real geometry even when `Info.plist`'s `LSUIElement` keeps it from ever being
    /// shown (confirmed empirically — see `DockIconController`), so `.onAppear` fires whether or
    /// not the user ever actually opens the dashboard. Using that would widen polling to every
    /// metric at full cadence from the very first launch, permanently defeating 3g. Promoting
    /// only on `didBecomeKeyNotification` and narrowing on `willCloseNotification` mirrors
    /// `DockIconController`'s fix for the identical problem, and the window being open widens
    /// polling to every metric at the user's foreground refresh rate (3g), regardless of which
    /// subset is enabled in the menu bar.
    func registerDashboardWindow(_ window: NSWindow) {
        dashboardWindow = window
        let id = ObjectIdentifier(window)
        guard dashboardWindowObservers[id] == nil else { return }

        let becomeKey = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.markDashboardWindowVisible(id: id) }
        }
        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.markDashboardWindowClosed(id: id) }
        }
        // `queue: .main` guarantees both closures run on the main thread; `assumeIsolated` tells
        // the compiler what the runtime already guarantees, since a `@Sendable` closure passed to
        // `addObserver` isn't statically known to be MainActor-isolated.
        dashboardWindowObservers[id] = [becomeKey, willClose]

        if window.isKeyWindow {
            markDashboardWindowVisible(id: id)
        }
    }

    /// Brings the single, pre-created dashboard window forward, in preference to the menu bar
    /// popup's `openWindow(id:)` fallback: `WindowGroup(id:)` treats every `openWindow(id:)` call
    /// as a request for a new window rather than a request to reuse an existing one, so routing
    /// the popup's "Open Dashboard" button through it left a fresh, silently orphaned window
    /// stacked behind the visible one on every click. Returns whether a window was available to
    /// present, so the caller can fall back to `openWindow(id:)` if this ever races ahead of the
    /// window's first registration.
    @discardableResult
    func presentDashboardWindow() -> Bool {
        guard let dashboardWindow else { return false }
        dashboardWindow.makeKeyAndOrderFront(nil)
        return true
    }

    private func markDashboardWindowVisible(id: ObjectIdentifier) {
        guard !visibleDashboardWindowIDs.contains(id) else { return }
        visibleDashboardWindowIDs.insert(id)
        isDashboardVisible = true
        recomputePollingState()
    }

    private func markDashboardWindowClosed(id: ObjectIdentifier) {
        visibleDashboardWindowIDs.remove(id)
        if let windowObservers = dashboardWindowObservers.removeValue(forKey: id) {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
        }
        if visibleDashboardWindowIDs.isEmpty {
            isDashboardVisible = false
            recomputePollingState()
        }
    }

    /// Wired to the menu bar popup's `onAppear`/`onDisappear`, once per menu bar item since
    /// each `MenuBarExtra` owns a separate popup window. Opening a popup always widens polling
    /// to every metric for as long as one is open — it's a full glance view, not scoped to the
    /// menu bar's enabled subset (3c) — independent of whether the dashboard is open.
    ///
    /// Publishing the newly-opened `kind` is also how the *other* popups learn to close: macOS
    /// does not dismiss one menu bar item's popup when a different item is clicked, so without
    /// this every enabled metric could have its own copy on screen at once.
    func handlePopupVisibilityChange(isVisible: Bool, kind: MetricKind) {
        if isVisible {
            visiblePopupKinds.insert(kind)
            frontmostPopupKind = kind
        } else {
            visiblePopupKinds.remove(kind)
            // Only clear if this was the frontmost one: the outgoing popup in a hand-off
            // disappears *after* the incoming one has already claimed the slot.
            if frontmostPopupKind == kind {
                frontmostPopupKind = nil
            }
        }
        recomputePollingState()
    }

    /// The single place that decides what `MetricsEngine` should be doing, re-run on every
    /// input that can change the answer: dashboard/popup visibility and menu bar config edits.
    /// - Dashboard or popup open: poll every metric at the user's foreground refresh rate.
    /// - Otherwise: poll exactly the menu bar's enabled subset (3h) at the slower background
    ///   cadence (3g), or pause entirely (3e) if nothing is enabled.
    private func recomputePollingState() {
        guard let metricsEngine = dependencies.metricsEngine else { return }

        let wantsFullCoverage = isDashboardVisible || !visiblePopupKinds.isEmpty
        let enabledMenuBarMetrics = Set(MetricKind.allCases.filter { settingsStore.menuBarConfig(for: $0).isEnabled })
        let activeMetrics = wantsFullCoverage ? Set(MetricKind.allCases) : enabledMenuBarMetrics
        let shouldPoll = !isDisplayUnavailable && (wantsFullCoverage || !enabledMenuBarMetrics.isEmpty)
        let cadence = wantsFullCoverage ? settingsStore.cadencePolicy : Self.backgroundCadencePolicy

        updateLiveViewActivity(isActive: wantsFullCoverage)

        Task {
            guard shouldPoll else {
                await metricsEngine.pause()
                return
            }
            await metricsEngine.setActiveMetrics(activeMetrics)
            await metricsEngine.updateCadence(cadence)
            await metricsEngine.resume()
        }
    }

    /// Begins/ends a `ProcessInfo` activity token spanning exactly the time the popup or
    /// dashboard is open. `LSUIElement` accessory apps remain subject to App Nap even with a
    /// `MenuBarExtra` popup on screen, and App Nap throttles `Task.sleep`-driven timers — which
    /// stretches the fast loop's real cadence past its nominal interval without erroring. Since
    /// `MetricRingBuffer` evicts purely on wall-clock age, a stretched cadence permanently caps
    /// how full the history chart gets rather than being a blip it later recovers from; this
    /// token tells the OS this process is doing user-visible work so its timers stay on time.
    private func updateLiveViewActivity(isActive: Bool) {
        if isActive {
            guard liveViewActivity == nil else { return }
            // `.userInitiatedAllowingIdleSystemSleep` exempts this process from App Nap without
            // also overriding the system's own sleep policy — the dashboard can stay open
            // indefinitely without that keeping the Mac itself awake.
            liveViewActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Live metrics view open"
            )
        } else if let activity = liveViewActivity {
            ProcessInfo.processInfo.endActivity(activity)
            liveViewActivity = nil
        }
    }
}

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

    private var isDashboardVisible = false
    private var isPopupVisible = false
    private var visibleDashboardWindowIDs: Set<ObjectIdentifier> = []
    private var dashboardWindowObservers: [ObjectIdentifier: [NSObjectProtocol]] = [:]

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
            recomputePollingState()
        }
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

    /// Wired to the menu bar popup's `onAppear`/`onDisappear`. Opening the popup always widens
    /// polling to every metric for as long as it's open — it's a full glance view, not scoped
    /// to the menu bar's enabled subset (3c) — independent of whether the dashboard is open.
    func handlePopupVisibilityChange(isVisible: Bool) {
        isPopupVisible = isVisible
        recomputePollingState()
    }

    /// The single place that decides what `MetricsEngine` should be doing, re-run on every
    /// input that can change the answer: dashboard/popup visibility and menu bar config edits.
    /// - Dashboard or popup open: poll every metric at the user's foreground refresh rate.
    /// - Otherwise: poll exactly the menu bar's enabled subset (3h) at the slower background
    ///   cadence (3g), or pause entirely (3e) if nothing is enabled.
    private func recomputePollingState() {
        guard let metricsEngine = dependencies.metricsEngine else { return }

        let wantsFullCoverage = isDashboardVisible || isPopupVisible
        let enabledMenuBarMetrics = Set(MetricKind.allCases.filter { settingsStore.menuBarConfig(for: $0).isEnabled })
        let activeMetrics = wantsFullCoverage ? Set(MetricKind.allCases) : enabledMenuBarMetrics
        let shouldPoll = wantsFullCoverage || !enabledMenuBarMetrics.isEmpty
        let cadence = wantsFullCoverage ? settingsStore.cadencePolicy : Self.backgroundCadencePolicy

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
}

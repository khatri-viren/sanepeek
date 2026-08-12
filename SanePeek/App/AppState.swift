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
        fixtureSnapshot: MetricFixtures.baseline()
    )

    /// Builds the shared metrics tick feed for this dependency set: the live
    /// engine when one is present, otherwise a fixture feed over
    /// `fixtureSnapshot` (falling back to the baseline fixture).
    @MainActor
    func makeMetricsTickFeed() -> any MetricsTickFeed {
        if let metricsEngine {
            return LiveMetricsTickFeed(engine: metricsEngine)
        }
        return FixtureMetricsTickFeed(baseline: fixtureSnapshot ?? MetricFixtures.baseline())
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

    /// UI tests can use `-uiTestFixture <name>` to force `.preview` runtime over a specific
    /// `MetricFixtures` scenario instead of `.live`. They can also pass
    /// `-uiTestSettingsSuite <name>` for an isolated, resettable settings store.
    static func forLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        let settingsSuiteName = value(after: "-uiTestSettingsSuite", in: arguments)

        guard let flagIndex = arguments.firstIndex(of: "-uiTestFixture"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return Self.live.withSettingsDefaultsSuiteName(settingsSuiteName)
        }

        let snapshot: MetricsSnapshot
        switch arguments[flagIndex + 1] {
        case "baseline":
            snapshot = MetricFixtures.baseline()
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

    /// The single shared ticking view model. Every menu-bar status item and compact popover
    /// reads this instance rather than constructing its own metrics stream.
    let metricsViewModel: MetricsViewModel

    /// Cadence used while only menu-bar items are visible — deliberately slower than the user's
    /// foreground refresh-rate setting, to bound the always-on idle cost of live status items.
    private static let backgroundCadencePolicy = CadencePolicy(refreshRate: .fiveSeconds)

    /// Low Power Mode clamps the fast tier to five seconds without changing the user's saved
    /// refresh-rate preference. The policy still pauses when there is no visible surface and no
    /// enabled menu-bar metric.
    private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Monotonically identifies desired activity snapshots submitted to `MetricsEngine`.
    /// The engine uses this generation to ignore an older task that reaches its actor after a
    /// newer lifecycle event.
    private var monitoringActivityGeneration: UInt64 = 0

    /// The shared AppKit popover's active session. Keeping the opening ID means a delayed close
    /// notification cannot clear a newer presentation after a rapid status-item hand-off.
    private var visiblePopupSession: (kind: MetricKind, id: UInt64)?
    private var nextPopupSessionID: UInt64 = 0

    /// True while the display is asleep or the session is locked — states in which nothing the
    /// engine drives can be seen, so polling is paused outright rather than merely narrowed.
    private var isDisplayUnavailable = false

    // `nonisolated(unsafe)` matches the view-model consumer task: these are only mutated from
    // MainActor code, but `deinit` is nonisolated and still needs to remove the observers.
    @ObservationIgnored
    private nonisolated(unsafe) var displayAvailabilityObservers: [NSObjectProtocol] = []

    /// Held only while the compact popover is open. Accessory apps remain subject to App Nap
    /// even while a menu-bar popover is on screen, which can stretch `Task.sleep`-driven timers
    /// beyond their nominal cadence and permanently reduce the chart history density.
    @ObservationIgnored
    private nonisolated(unsafe) var liveViewActivity: NSObjectProtocol?

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
        let settingsStore = dependencies.makeSettingsStore()
        self.settingsStore = settingsStore
        self.metricsViewModel = MetricsViewModel(
            feed: dependencies.makeMetricsTickFeed(),
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
    /// conventionally observed through these distributed notifications. Low Power Mode is
    /// observed through ProcessInfo's power-state notification.
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
        let powerStateChanged = center.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setLowPowerModeEnabled(ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
        }
        displayAvailabilityObservers = [sleep, wake, locked, unlocked, powerStateChanged]
    }

    private func setDisplayUnavailable(_ unavailable: Bool) {
        guard isDisplayUnavailable != unavailable else { return }
        isDisplayUnavailable = unavailable
        recomputePollingState()
    }

    private func setLowPowerModeEnabled(_ enabled: Bool) {
        guard isLowPowerModeEnabled != enabled else { return }
        isLowPowerModeEnabled = enabled
        recomputePollingState()
    }

    /// Wired to the shared menu-bar popover's lifecycle. Opening it widens polling to every
    /// metric for as long as it is open — it is a full glance view, not scoped to the enabled
    /// menu-bar subset.
    @discardableResult
    func popupDidAppear(kind: MetricKind) -> UInt64 {
        nextPopupSessionID &+= 1
        let sessionID = nextPopupSessionID
        visiblePopupSession = (kind, sessionID)
        recomputePollingState()
        return sessionID
    }

    func popupDidDisappear(kind: MetricKind, sessionID: UInt64) {
        // Ignore a delayed callback belonging to an older presentation.
        guard visiblePopupSession?.kind == kind,
              visiblePopupSession?.id == sessionID
        else { return }

        visiblePopupSession = nil
        recomputePollingState()
    }

    func isPopupVisible(kind: MetricKind) -> Bool {
        visiblePopupSession?.kind == kind
    }

    /// Resolves what `MetricsEngine` should be doing whenever popup visibility, menu-bar config,
    /// refresh rate, display availability, or Low Power Mode changes.
    private func recomputePollingState() {
        guard let metricsEngine = dependencies.metricsEngine else { return }

        let enabledMenuBarMetrics = Set(MetricKind.allCases.filter { settingsStore.menuBarConfig(for: $0).isEnabled })
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(
                isPopupVisible: visiblePopupSession != nil,
                enabledMenuBarMetrics: enabledMenuBarMetrics,
                isDisplayAvailable: !isDisplayUnavailable,
                isLowPowerModeEnabled: isLowPowerModeEnabled,
                foregroundCadence: settingsStore.cadencePolicy,
                backgroundCadence: Self.backgroundCadencePolicy
            )
        )

        updateLiveViewActivity(isActive: activity.isForeground)

        monitoringActivityGeneration &+= 1
        let generation = monitoringActivityGeneration
        Task {
            await metricsEngine.reconcileMonitoringActivity(activity, generation: generation)
        }
    }

    /// Begins/ends a `ProcessInfo` activity token spanning exactly the time the popup is open.
    private func updateLiveViewActivity(isActive: Bool) {
        if isActive {
            guard liveViewActivity == nil else { return }
            // This exempts the process from App Nap without overriding the system's own sleep
            // policy, so an open popup does not keep the Mac awake.
            liveViewActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Live metrics popup open"
            )
        } else if let activity = liveViewActivity {
            ProcessInfo.processInfo.endActivity(activity)
            liveViewActivity = nil
        }
    }
}

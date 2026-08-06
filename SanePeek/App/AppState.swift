//
//  AppState.swift
//  SanePeek
//

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

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
        let settingsStore = dependencies.makeSettingsStore()
        self.settingsStore = settingsStore

        if let metricsEngine = dependencies.metricsEngine {
            settingsStore.onRefreshRateChange = { refreshRate in
                Task { await metricsEngine.updateCadence(CadencePolicy(refreshRate: refreshRate)) }
            }
            Task { await metricsEngine.updateCadence(settingsStore.cadencePolicy) }
        }
    }

    /// Wired to window/scene visibility so polling stops while the dashboard
    /// isn't visible instead of running unnecessarily in the background.
    func handlePollingVisibilityChange(isVisible: Bool) {
        guard let metricsEngine = dependencies.metricsEngine else { return }
        Task {
            if isVisible {
                await metricsEngine.resume()
            } else {
                await metricsEngine.pause()
            }
        }
    }
}

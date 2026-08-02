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

    init(
        runtime: AppRuntime,
        fixtureSnapshot: MetricsSnapshot? = nil,
        metricsEngine: MetricsEngine? = nil
    ) {
        self.runtime = runtime
        self.fixtureSnapshot = fixtureSnapshot
        self.metricsEngine = metricsEngine
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

    /// UI tests can't rely on real hardware state (GPU support, battery
    /// presence, thresholds) being deterministic, so they launch with
    /// `-uiTestFixture <name>` to force `.preview` runtime over a specific
    /// `MetricFixtures` scenario instead of `.live`.
    static func forLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        guard let flagIndex = arguments.firstIndex(of: "-uiTestFixture"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return .live
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
        default:
            return .live
        }

        return Self(runtime: .preview, fixtureSnapshot: snapshot)
    }
}

@MainActor
@Observable
final class AppState {
    let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }
}

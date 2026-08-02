//
//  AppState.swift
//  SanePeek
//

import Observation

enum AppRuntime: String, Equatable, Sendable {
    case live
    case preview
}

/// The composition boundary for application-wide dependencies.
///
/// Phase 1 will add the metric contracts that are selected here. Keeping the
/// boundary in place now lets previews and tests avoid global singletons.
struct AppDependencies: Sendable {
    let runtime: AppRuntime
    let fixtureSnapshot: MetricsSnapshot?

    init(runtime: AppRuntime, fixtureSnapshot: MetricsSnapshot? = nil) {
        self.runtime = runtime
        self.fixtureSnapshot = fixtureSnapshot
    }

    static let live = Self(runtime: .live)
    static let preview = Self(
        runtime: .preview,
        fixtureSnapshot: MetricFixtures.dashboard()
    )
}

@MainActor
@Observable
final class AppState {
    let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }
}

import Foundation
import Testing

@testable import SanePeek

@Suite("Deterministic test support")
struct TestSupportTests {
    @Test("Every launch fixture maps to a distinct deterministic snapshot")
    @MainActor
    func fixtureMatrixIsComplete() {
        let scenarios = TestFixtureScenario.allCases
        #expect(scenarios.count == 7)
        #expect(Set(scenarios.map(\.rawValue)).count == scenarios.count)

        for scenario in scenarios {
            let dependencies = AppDependencies.forLaunch(arguments: scenario.launchArguments)
            #expect(dependencies.runtime == .preview)
            #expect(dependencies.fixtureSnapshot == scenario.snapshot)
        }

        for (index, scenario) in scenarios.enumerated() {
            for otherScenario in scenarios.dropFirst(index + 1) {
                #expect(scenario.snapshot != otherScenario.snapshot)
            }
        }
    }

    @Test("An isolated defaults suite does not touch standard preferences")
    @MainActor
    func defaultsAreIsolated() {
        let suite = TestDefaultsSuite()
        defer { suite.removePersistentDomain() }

        suite.defaults.set("test-only", forKey: "test.key")

        #expect(suite.defaults.string(forKey: "test.key") == "test-only")
        #expect(UserDefaults.standard.string(forKey: "test.key") == nil)
    }

    @Test("The scheduler advances only when the test releases a tick")
    func schedulerIsControlled() async throws {
        let scheduler = TestMetricScheduler()

        let waitTask = Task {
            try await scheduler.wait(for: 2.5)
        }

        #expect(await TestAsync.waitUntil {
            await scheduler.requestedIntervals() == [2.5]
        })
        #expect(!waitTask.isCancelled)

        await scheduler.releaseNext()
        try await waitTask.value

        #expect(await scheduler.requestedIntervals() == [2.5])
    }

    @Test("A queued reader records timestamps and returns results in order")
    func readerDoubleIsDeterministic() async {
        let timestamp = MetricTimestamp.zero
        let reader = TestMetricReader<CPUSnapshot>(results: [
            .unavailable(.noData),
            .failed(MetricFailure(kind: .timedOut))
        ])

        let first = await reader.read(at: timestamp)
        let second = await reader.read(at: timestamp.advanced(by: 1))
        let count = await reader.recorder.readCount()

        #expect(first.availability == .unavailable(.noData))
        #expect(second.availability == .failed(MetricFailure(kind: .timedOut)))
        #expect(count == 2)
    }

    @Test("The launch-at-login double records operations without using SMAppService")
    @MainActor
    func launchAtLoginDoubleIsControlled() throws {
        let service = TestLaunchAtLoginService()
        try service.register()
        try service.unregister()

        #expect(service.registerCallCount == 1)
        #expect(service.unregisterCallCount == 1)
        #expect(service.status == .notRegistered)
    }

    @Test("The updater double exposes state and records checks without starting Sparkle")
    @MainActor
    func updaterDoubleIsControlled() {
        let updater = TestUpdaterService(canCheckForUpdates: false, currentVersion: "test (42)")

        updater.checkForUpdates()

        #expect(updater.canCheckForUpdates == false)
        #expect(updater.currentVersion == "test (42)")
        #expect(updater.checkForUpdatesCallCount == 1)
    }
}

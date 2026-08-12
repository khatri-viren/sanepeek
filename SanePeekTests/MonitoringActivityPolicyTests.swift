//
//  MonitoringActivityPolicyTests.swift
//  SanePeekTests
//

import Testing
@testable import SanePeek

struct MonitoringActivityPolicyTests {
    @Test("No enabled menu bar metrics pauses background monitoring")
    func noEnabledMetricsPausesMonitoring() {
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(enabledMenuBarMetrics: [])
        )

        #expect(activity == .paused)
    }

    @Test("Background monitoring reads only enabled metrics at the fixed background cadence")
    func backgroundMonitoringUsesEnabledMetricsAndBackgroundCadence() {
        let enabledMetrics: Set<MetricKind> = [.cpu, .temperature]
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(enabledMenuBarMetrics: enabledMetrics)
        )

        #expect(
            activity == .background(
                activeMetrics: enabledMetrics,
                cadence: CadencePolicy(refreshRate: .fiveSeconds)
            )
        )
    }

    @Test("A visible popup widens monitoring to all metrics at the foreground cadence")
    func popupUsesFullCoverageAndForegroundCadence() {
        let foregroundCadence = CadencePolicy(refreshRate: .twoSeconds)
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(
                isPopupVisible: true,
                enabledMenuBarMetrics: [.cpu],
                foregroundCadence: foregroundCadence
            )
        )

        #expect(activity == .foreground(cadence: foregroundCadence))
        #expect(activity.activeMetrics == Set(MetricKind.allCases))
    }

    @Test("Low Power Mode clamps foreground fast cadence without changing coverage")
    func lowPowerModeClampsForegroundCadence() {
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(
                isPopupVisible: true,
                isLowPowerModeEnabled: true,
                foregroundCadence: CadencePolicy(refreshRate: .oneSecond)
            )
        )

        #expect(activity == .foreground(cadence: CadencePolicy(refreshRate: .fiveSeconds)))
        #expect(activity.activeMetrics == Set(MetricKind.allCases))
    }

    @Test("Low Power Mode preserves a foreground cadence already at five seconds")
    func lowPowerModePreservesFiveSecondForegroundCadence() {
        let cadence = CadencePolicy(refreshRate: .fiveSeconds)
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(
                isPopupVisible: true,
                isLowPowerModeEnabled: true,
                foregroundCadence: cadence
            )
        )

        #expect(activity == .foreground(cadence: cadence))
    }

    @Test("A visible popup uses full-coverage monitoring")
    func popupUsesFullCoverage() {
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(
                isPopupVisible: true,
                enabledMenuBarMetrics: [.memory]
            )
        )

        #expect(activity.isForeground)
        #expect(activity.activeMetrics == Set(MetricKind.allCases))
    }

    @Test("Low Power Mode keeps all metrics active for demanded background monitoring")
    func lowPowerModeUsesFullBackgroundCoverage() {
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(
                enabledMenuBarMetrics: [.cpu],
                isLowPowerModeEnabled: true
            )
        )

        #expect(
            activity == .background(
                activeMetrics: Set(MetricKind.allCases),
                cadence: CadencePolicy(refreshRate: .fiveSeconds)
            )
        )
    }

    @Test("Low Power Mode does not create polling when there is no monitoring demand")
    func lowPowerModePreservesNoDemandPause() {
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(isLowPowerModeEnabled: true)
        )

        #expect(activity == .paused)
    }

    @Test("Display unavailability pauses even when a foreground view is visible")
    func unavailableDisplayPausesMonitoring() {
        let activity = MonitoringActivityPolicy.resolve(
            MonitoringActivityInputs(
                isPopupVisible: true,
                enabledMenuBarMetrics: Set(MetricKind.allCases),
                isDisplayAvailable: false
            )
        )

        #expect(activity == .paused)
    }
}

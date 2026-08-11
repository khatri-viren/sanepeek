//
//  MonitoringActivityPolicy.swift
//  SanePeek
//

import Foundation

/// The monitoring activity that the engine should execute for the current set of lifecycle
/// inputs. The policy is intentionally a value: callers can resolve it synchronously and submit
/// one complete desired state to `MetricsEngine` without making the engine know about windows,
/// popovers, or settings.
nonisolated enum MonitoringActivityState: Equatable, Sendable {
    case paused
    case background(activeMetrics: Set<MetricKind>, cadence: CadencePolicy)
    case foreground(cadence: CadencePolicy)

    var activeMetrics: Set<MetricKind> {
        switch self {
        case .paused:
            []
        case let .background(activeMetrics, _):
            activeMetrics
        case .foreground:
            Set(MetricKind.allCases)
        }
    }

    var cadence: CadencePolicy? {
        switch self {
        case .paused:
            nil
        case let .background(_, cadence), let .foreground(cadence):
            cadence
        }
    }

    var isForeground: Bool {
        if case .foreground = self {
            return true
        }
        return false
    }
}

/// Inputs that can change the desired monitoring activity. Platform notifications and UI
/// lifecycle callbacks are adapters that populate this value; they do not directly mutate the
/// engine.
nonisolated struct MonitoringActivityInputs: Equatable, Sendable {
    let isDashboardVisible: Bool
    let isPopupVisible: Bool
    let enabledMenuBarMetrics: Set<MetricKind>
    let isDisplayAvailable: Bool
    let isLowPowerModeEnabled: Bool
    let foregroundCadence: CadencePolicy
    let backgroundCadence: CadencePolicy

    init(
        isDashboardVisible: Bool = false,
        isPopupVisible: Bool = false,
        enabledMenuBarMetrics: Set<MetricKind> = [],
        isDisplayAvailable: Bool = true,
        isLowPowerModeEnabled: Bool = false,
        foregroundCadence: CadencePolicy = CadencePolicy(),
        backgroundCadence: CadencePolicy = CadencePolicy(refreshRate: .fiveSeconds)
    ) {
        self.isDashboardVisible = isDashboardVisible
        self.isPopupVisible = isPopupVisible
        self.enabledMenuBarMetrics = enabledMenuBarMetrics
        self.isDisplayAvailable = isDisplayAvailable
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.foregroundCadence = foregroundCadence
        self.backgroundCadence = backgroundCadence
    }

    var hasForegroundView: Bool {
        isDashboardVisible || isPopupVisible
    }
}

/// Resolves lifecycle and settings inputs into the one activity state the metrics engine should
/// execute. This module has no AppKit, SwiftUI, or reader dependencies, which keeps the policy
/// testable without a real window or hardware-backed metric engine.
nonisolated enum MonitoringActivityPolicy {
    static func resolve(_ inputs: MonitoringActivityInputs) -> MonitoringActivityState {
        guard inputs.isDisplayAvailable else {
            return .paused
        }

        // Low Power Mode changes how an already-demanded activity runs; it does not create a
        // demand when every visible surface is closed and no menu-bar metric is enabled.
        guard inputs.hasForegroundView || !inputs.enabledMenuBarMetrics.isEmpty else {
            return .paused
        }

        if inputs.hasForegroundView {
            return .foreground(cadence: effectiveForegroundCadence(for: inputs))
        }

        if inputs.isLowPowerModeEnabled {
            return .background(
                activeMetrics: Set(MetricKind.allCases),
                cadence: lowPowerCadence(for: inputs.backgroundCadence)
            )
        }

        return .background(
            activeMetrics: inputs.enabledMenuBarMetrics,
            cadence: inputs.backgroundCadence
        )
    }

    private static func effectiveForegroundCadence(for inputs: MonitoringActivityInputs) -> CadencePolicy {
        guard inputs.isLowPowerModeEnabled else {
            return inputs.foregroundCadence
        }
        return lowPowerCadence(for: inputs.foregroundCadence)
    }

    private static func lowPowerCadence(for cadence: CadencePolicy) -> CadencePolicy {
        guard cadence.refreshRate.rawValue < RefreshRate.fiveSeconds.rawValue else {
            return cadence
        }
        return CadencePolicy(refreshRate: .fiveSeconds)
    }
}

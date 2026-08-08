import Foundation

nonisolated enum RefreshRate: Int, CaseIterable, Equatable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5

    var interval: TimeInterval {
        TimeInterval(rawValue)
    }
}

nonisolated struct CadencePolicy: Equatable, Sendable {
    let refreshRate: RefreshRate

    init(refreshRate: RefreshRate = .oneSecond) {
        self.refreshRate = refreshRate
    }

    /// Temperature follows the user's refresh rate, but never polls faster than this.
    ///
    /// A sample is nine synchronous SMC round trips at ~0.20 ms each (measured 2026-08-08), so
    /// 1 Hz would cost ~0.21% CPU — roughly the app's entire idle budget again — to track a
    /// value that moved only ~1.5 °C per two seconds even under full load. Two seconds keeps it
    /// feeling live for about half that cost.
    static let temperatureMinimumInterval: TimeInterval = 2

    func interval(for metric: MetricKind) -> TimeInterval {
        switch metric {
        case .cpu, .memory, .network, .gpu:
            refreshRate.interval
        case .temperature:
            max(refreshRate.interval, Self.temperatureMinimumInterval)
        case .storage, .battery:
            30
        }
    }
}

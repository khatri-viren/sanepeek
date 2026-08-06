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

    func interval(for metric: MetricKind) -> TimeInterval {
        switch metric {
        case .cpu, .memory, .network, .gpu:
            refreshRate.interval
        case .storage, .battery, .temperature:
            30
        }
    }
}

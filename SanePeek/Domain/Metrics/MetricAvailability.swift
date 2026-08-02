import Foundation

nonisolated enum MetricUnavailableReason: String, Equatable, Sendable {
    case unsupported
    case notPresent
    case noData
    case temporarilyUnavailable
    case notApplicable

    var userMessage: String {
        switch self {
        case .unsupported:
            "This metric is not supported on this Mac."
        case .notPresent:
            "This metric is not present."
        case .noData:
            "No data is available yet."
        case .temporarilyUnavailable:
            "This metric is temporarily unavailable."
        case .notApplicable:
            "This metric is not applicable."
        }
    }
}

nonisolated enum MetricFailureKind: String, Equatable, Sendable {
    case systemUnavailable
    case permissionDenied
    case invalidData
    case timedOut
    case cancelled
}

nonisolated struct MetricFailure: Error, Equatable, Sendable {
    let kind: MetricFailureKind

    init(kind: MetricFailureKind) {
        self.kind = kind
    }

    var userMessage: String {
        switch kind {
        case .systemUnavailable, .timedOut, .cancelled:
            "This metric is temporarily unavailable."
        case .permissionDenied:
            "This metric is unavailable due to system permissions."
        case .invalidData:
            "The metric data is unavailable."
        }
    }
}

nonisolated enum MetricAvailability: Equatable, Sendable {
    case available
    case unavailable(MetricUnavailableReason)
    case failed(MetricFailure)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var userMessage: String? {
        switch self {
        case .available:
            nil
        case let .unavailable(reason):
            reason.userMessage
        case let .failed(failure):
            failure.userMessage
        }
    }
}

nonisolated enum MetricResult<Value: Sendable>: Sendable {
    case available(Value)
    case unavailable(MetricUnavailableReason)
    case failed(MetricFailure)

    var value: Value? {
        if case let .available(value) = self {
            return value
        }
        return nil
    }

    var availability: MetricAvailability {
        switch self {
        case .available:
            .available
        case let .unavailable(reason):
            .unavailable(reason)
        case let .failed(failure):
            .failed(failure)
        }
    }

    var isAvailable: Bool {
        availability.isAvailable
    }

    var userMessage: String? {
        availability.userMessage
    }
}

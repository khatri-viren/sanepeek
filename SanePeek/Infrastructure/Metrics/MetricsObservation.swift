import Foundation

/// History series published alongside one `MetricsSnapshot`. The engine owns the storage and
/// creates this value inside the same actor turn as the snapshot, so consumers cannot accidentally
/// pair a snapshot with histories from a later publication.
nonisolated struct MetricsObservation: Sendable, Equatable {
    let snapshot: MetricsSnapshot
    private let histories: [MetricHistoryKind: [MetricSample<Double>]]

    init(
        snapshot: MetricsSnapshot,
        histories: [MetricHistoryKind: [MetricSample<Double>]]
    ) {
        self.snapshot = snapshot
        self.histories = histories
    }

    /// Returns a copy of the bounded series for a semantic history kind. Missing or inactive
    /// kinds are represented as an empty series rather than exposing the engine's ring buffers.
    func history(for kind: MetricHistoryKind) -> [MetricSample<Double>] {
        histories[kind] ?? []
    }
}

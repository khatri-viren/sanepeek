nonisolated protocol MetricReader: Sendable {
    associatedtype Snapshot: MetricSnapshot

    func read(at timestamp: MetricTimestamp) async -> MetricResult<Snapshot>
}

nonisolated protocol SynchronousMetricReader: Sendable {
    associatedtype Snapshot: MetricSnapshot

    func read(at timestamp: MetricTimestamp) -> MetricResult<Snapshot>
}

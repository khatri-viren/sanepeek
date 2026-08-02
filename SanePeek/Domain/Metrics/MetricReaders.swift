nonisolated protocol MetricReader: Sendable {
    associatedtype Snapshot: MetricSnapshot

    func read(at timestamp: MetricTimestamp) async -> MetricResult<Snapshot>
}

nonisolated protocol SynchronousMetricReader: Sendable {
    associatedtype Snapshot: MetricSnapshot

    func read(at timestamp: MetricTimestamp) -> MetricResult<Snapshot>
}

nonisolated protocol CPUReader: MetricReader where Snapshot == CPUSnapshot {}

nonisolated protocol MemoryReader: MetricReader where Snapshot == MemorySnapshot {}

nonisolated protocol StorageReader: MetricReader where Snapshot == StorageSnapshot {}

nonisolated protocol NetworkReader: MetricReader where Snapshot == NetworkSnapshot {}

nonisolated protocol BatteryReader: MetricReader where Snapshot == BatterySnapshot {}

nonisolated protocol GPUReader: MetricReader where Snapshot == GPUSnapshot {}

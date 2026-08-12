/// One tick of shared metrics data: a snapshot plus the per-kind history arrays
/// needed to draw sparklines. Produced by any `MetricsTickFeed` —
/// `FixtureMetricsTickFeed` for previews/UI tests, `LiveMetricsTickFeed`
/// for the real `MetricsEngine`.
nonisolated struct MetricsTick: Sendable, Equatable {
    let snapshot: MetricsSnapshot
    let cpuHistory: [Double]
    let cpuUserHistory: [Double]
    let cpuSystemHistory: [Double]
    let memoryHistory: [Double]
    let memoryAppHistory: [Double]
    let memoryWiredHistory: [Double]
    let memoryCompressedHistory: [Double]
    let networkDownloadHistory: [Double]
    let networkUploadHistory: [Double]
    let gpuHistory: [Double]
    let temperatureHistory: [Double]
}

/// One tick of dashboard data: a snapshot plus the per-kind history arrays
/// needed to draw sparklines. Produced by any `DashboardTickFeed` —
/// `FixtureDashboardTickFeed` for previews/UI tests, `LiveDashboardTickFeed`
/// for the real `MetricsEngine`.
nonisolated struct DashboardTick: Sendable, Equatable {
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

/// One tick of dashboard data: a snapshot plus the per-kind history arrays
/// needed to draw sparklines. Produced by any `DashboardTickFeed` —
/// `FixtureDashboardTickFeed` for previews/UI tests, `LiveDashboardTickFeed`
/// for the real `MetricsEngine`.
nonisolated struct DashboardTick: Sendable, Equatable {
    let snapshot: MetricsSnapshot
    let cpuHistory: [Double]
    let memoryHistory: [Double]
    let networkDownloadHistory: [Double]
    let gpuHistory: [Double]
}

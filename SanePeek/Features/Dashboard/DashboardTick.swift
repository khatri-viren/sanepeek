/// One tick of dashboard data: a snapshot plus the per-kind history arrays
/// needed to draw sparklines. Phase 4 only ever gets these from
/// `FixtureDashboardTickFeed`; wiring a live source is Phase 5's job.
nonisolated struct DashboardTick: Sendable, Equatable {
    let snapshot: MetricsSnapshot
    let cpuHistory: [Double]
    let memoryHistory: [Double]
    let networkDownloadHistory: [Double]
    let gpuHistory: [Double]
}

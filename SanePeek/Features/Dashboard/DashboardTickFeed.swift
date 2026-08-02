/// Something `DashboardViewModel` can consume a stream of `DashboardTick`s from,
/// whether backed by fixtures (previews) or a live `MetricsEngine`.
@MainActor
protocol DashboardTickFeed: AnyObject {
    func ticks() -> AsyncStream<DashboardTick>
}

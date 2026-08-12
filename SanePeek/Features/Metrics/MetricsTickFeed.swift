/// Something `MetricsViewModel` can consume a stream of `MetricsTick`s from,
/// whether backed by fixtures (previews) or a live `MetricsEngine`.
@MainActor
protocol MetricsTickFeed: AnyObject {
    func ticks() -> AsyncStream<MetricsTick>
}

/// Extra breakdown data `TemperatureCardView` needs beyond what the shared
/// `MetricCardModel` carries, mirroring `CPUCardDetail`/`MemoryCardDetail`'s role.
nonisolated struct TemperatureCardDetail: Equatable {
    /// Raw value, for the gauge needle's rotation math.
    let hottestCelsius: Double?
    /// Formatted, for the gauge's label and as a fallback for `primaryValue`.
    let hottestText: String
    let cpuText: String?
    let gpuText: String?
}

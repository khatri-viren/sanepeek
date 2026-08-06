/// User/system/idle breakdown and stacked-history samples for the CPU hero
/// card. Built by `MetricCardMapping.cpuDetail` from a domain snapshot plus
/// the tick's per-tick histories; nil when the breakdown can't be computed
/// (snapshot missing, unavailable, or the first sample before a delta exists).
nonisolated struct CPUCardDetail: Equatable {
    let chipName: String?
    let userPercentageText: String
    let systemPercentageText: String
    let idlePercentageText: String
    /// 0...1 fractions, oldest first, aligned index-for-index with `systemHistory`.
    let userHistory: [Double]
    let systemHistory: [Double]
}

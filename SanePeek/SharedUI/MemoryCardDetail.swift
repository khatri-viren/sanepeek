/// App/Wired/Compressed breakdown and stacked-history samples for the Memory
/// hero card. Built by `MetricCardMapping.memoryDetail` from a domain snapshot
/// plus the tick's per-tick histories; nil when the breakdown can't be
/// computed (snapshot missing, unavailable, or the breakdown fractions aren't
/// available yet).
nonisolated struct MemoryCardDetail: Equatable {
    let totalRAMText: String?
    let appPercentageText: String
    let wiredPercentageText: String
    let compressedPercentageText: String
    let freePercentageText: String
    /// 0...1 fractions, oldest first, aligned index-for-index with each other.
    let appHistory: [Double]
    let wiredHistory: [Double]
    let compressedHistory: [Double]
}

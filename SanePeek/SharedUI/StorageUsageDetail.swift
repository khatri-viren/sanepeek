/// Total/used/free byte breakdown for the menu bar popup's Storage detail view.
/// Built by `MetricCardMapping.storageCard` from a domain snapshot; nil when the
/// total or used byte counts aren't available yet.
nonisolated struct StorageUsageDetail: Equatable {
    let totalText: String
    let usedText: String
    let freeText: String
}

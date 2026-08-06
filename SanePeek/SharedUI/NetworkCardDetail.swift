nonisolated struct NetworkCardDetail: Equatable {
    /// Honest substitute for a Wi-Fi standard/band label: this app has no
    /// CoreWLAN/location entitlement, so this is the raw BSD interface name(s)
    /// (e.g. "en0"), or a connectivity word if none are reported. Nil when
    /// neither is available.
    let subtitleText: String?
    let downloadText: String
    /// Nil when uploadBytesPerSecond is nil — the view falls back to "--".
    let uploadText: String?
    let downloadHistory: [Double]
    let uploadHistory: [Double]
}

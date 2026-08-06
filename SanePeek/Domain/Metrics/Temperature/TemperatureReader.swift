nonisolated protocol TemperatureReader: MetricReader where Snapshot == TemperatureSnapshot {}

/// No public API exists for CPU/GPU temperature on Apple Silicon: the only paths (the
/// private `IOHIDEventSystemClient` framework, or an SMC dispatcher requiring an
/// Apple-granted entitlement) conflict with the PRD's "do not use private frameworks"
/// rule, and Temperature is explicitly scoped for V2, not V1. This honestly reports
/// unsupported until a compliant data source exists — a future implementation replaces
/// only this function body.
nonisolated struct LiveTemperatureReader: TemperatureReader {
    func read(at timestamp: MetricTimestamp) async -> MetricResult<TemperatureSnapshot> {
        .unavailable(.unsupported)
    }
}

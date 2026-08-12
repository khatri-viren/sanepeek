import Testing

@testable import SanePeek

@Suite("CPU domain")
struct CPUDomainTests {
    @Test("CPU breakdown folds nice ticks into user utilization")
    func breakdownFoldsNiceTicksIntoUserUtilization() {
        let previous = CPUCounterSample(
            timestamp: .zero,
            userTicks: 10,
            systemTicks: 10,
            idleTicks: 70,
            niceTicks: 10
        )
        let current = CPUCounterSample(
            timestamp: .zero.advanced(by: 1),
            userTicks: 20,
            systemTicks: 20,
            idleTicks: 140,
            niceTicks: 20
        )

        let result = CPUUtilizationCalculator.calculateBreakdown(from: previous, to: current)

        guard case let .available(breakdown) = result else {
            Issue.record("Expected a valid CPU utilization breakdown, got \(result)")
            return
        }

        #expect(abs(breakdown.user - 0.2) < 0.0001)
        #expect(abs(breakdown.system - 0.1) < 0.0001)
        #expect(abs(breakdown.total - 0.3) < 0.0001)
    }
}

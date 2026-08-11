import Testing

@testable import SanePeek

@Suite("Menu bar catalog")
struct MenuBarCatalogTests {
    @Test("Every metric kind has exactly one descriptor")
    func metricsHaveCompleteUniqueDescriptors() {
        let kinds = MenuBarCatalog.metrics.map(\.kind)

        #expect(kinds.count == MetricKind.allCases.count)
        #expect(Set(kinds) == Set(MetricKind.allCases))
        #expect(Set(kinds).count == kinds.count)
    }

    @Test("Every descriptor has a unique three-letter uppercase abbreviation")
    func descriptorsHaveValidAbbreviations() {
        let abbreviations = MenuBarCatalog.metrics.map(\.abbreviation)

        for descriptor in MenuBarCatalog.metrics {
            #expect(descriptor.settingsTitle.isEmpty == false)
            #expect(descriptor.abbreviation.count == 3, "\(descriptor.kind) is \(descriptor.abbreviation)")
            #expect(
                descriptor.abbreviation.allSatisfy { $0.isUppercase && $0.isLetter },
                "\(descriptor.kind) is \(descriptor.abbreviation)"
            )
        }

        #expect(Set(abbreviations).count == abbreviations.count)
    }

    @Test("The three presentation orders cover every metric exactly once")
    func presentationOrdersAreComplete() {
        let expectedKinds = Set(MetricKind.allCases)

        for order in [
            MenuBarCatalog.statusItemOrder,
            MenuBarCatalog.popoverOrder,
            MenuBarCatalog.settingsOrder
        ] {
            #expect(order.count == MetricKind.allCases.count)
            #expect(Set(order) == expectedKinds)
            #expect(Set(order).count == order.count)
        }
    }

    @Test("The current status-item order remains compact and explicit")
    func statusItemOrderIsStable() {
        #expect(MenuBarCatalog.statusItemOrder == [
            .cpu, .memory, .storage, .network, .battery, .gpu, .temperature
        ])
    }

    @Test("The popup and settings orders preserve dashboard grouping")
    func popupAndSettingsOrdersAreStable() {
        let expected: [MetricKind] = [.cpu, .memory, .temperature, .network, .storage, .battery, .gpu]

        #expect(MenuBarCatalog.popoverOrder == expected)
        #expect(MenuBarCatalog.settingsOrder == expected)
        #expect(MenuBarCatalog.popoverRows.map(\.kind) == expected)
        #expect(MenuBarCatalog.settingsRows.map(\.kind) == expected)
        #expect(MenuBarCatalog.settingsRows.map(\.settingsTitle) == [
            "CPU", "Memory", "Temperature", "Network", "Storage", "Battery", "GPU"
        ])
    }

    @Test("Descriptor lookup preserves non-obvious menu-bar abbreviations")
    func descriptorLookupReturnsExpectedMetadata() {
        #expect(MenuBarCatalog.descriptor(for: .memory).abbreviation == "RAM")
        #expect(MenuBarCatalog.descriptor(for: .storage).abbreviation == "SSD")
        #expect(MenuBarCatalog.descriptor(for: .temperature).abbreviation == "TMP")
    }
}

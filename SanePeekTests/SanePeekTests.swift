//
//  SanePeekTests.swift
//  SanePeekTests
//

import Testing
@testable import SanePeek

struct SanePeekTests {

    @Test("App state defaults to live dependencies")
    @MainActor
    func appStateUsesLiveDependenciesByDefault() {
        let appState = AppState()

        #expect(appState.dependencies.runtime == .live)
    }

    @Test("App state accepts preview dependencies")
    @MainActor
    func appStateAcceptsPreviewDependencies() {
        let appState = AppState(dependencies: .preview)

        #expect(appState.dependencies.runtime == .preview)
    }
}

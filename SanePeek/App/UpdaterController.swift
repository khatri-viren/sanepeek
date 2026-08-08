import Sparkle
import SwiftUI

/// Owns the Sparkle updater and exposes just enough of it for the UI to drive.
///
/// SanePeek is distributed as a direct download rather than through the App Store, so nothing
/// tells an installed copy that a new version exists — Sparkle polls the appcast published by
/// the release workflow and offers the update in place.
///
/// `SPUStandardUpdaterController` has to outlive the view that shows the button, so this is a
/// long-lived object hung off the app rather than state inside a view: recreating it would
/// restart the updater and drop any check already in flight.
@MainActor
@Observable
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    /// Mirrors the updater's own gate for the menu item's enabled state — Sparkle refuses
    /// overlapping checks, so the button has to go inert while one is running.
    private(set) var canCheckForUpdates = false

    private var observation: NSKeyValueObservation?

    init() {
        // `startingUpdater: true` begins the scheduled background checks immediately; the
        // user is asked for permission on first launch by Sparkle itself.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = value
            }
        }
    }

    /// The version string shown next to the check button, so the user can tell at a glance
    /// which build they're on when reporting something.
    var currentVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

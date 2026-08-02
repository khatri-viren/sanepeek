import Foundation
import Observation

/// Durable, typed user preferences. Persists to the injected `UserDefaults`
/// (a distinct suite in UI tests, `.standard` otherwise) and exposes derived
/// values (`formatter`, `cadencePolicy`) so consumers never touch raw defaults.
@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults
    private let launchAtLoginService: any LaunchAtLoginService

    var appearance: AppAppearance {
        didSet {
            guard appearance != oldValue else { return }
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
        }
    }

    var refreshRate: RefreshRate {
        didSet {
            guard refreshRate != oldValue else { return }
            defaults.set(refreshRate.rawValue, forKey: Keys.refreshRate)
            onRefreshRateChange?(refreshRate)
        }
    }

    var byteUnitSystem: ByteUnitSystem {
        didSet {
            guard byteUnitSystem != oldValue else { return }
            defaults.set(byteUnitSystem.rawValue, forKey: Keys.byteUnitSystem)
        }
    }

    var temperatureUnit: TemperatureUnit {
        didSet {
            guard temperatureUnit != oldValue else { return }
            defaults.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit)
        }
    }

    private(set) var launchAtLoginStatus: LaunchAtLoginStatus

    /// Set by `AppState` to route cadence changes into the live `MetricsEngine`.
    @ObservationIgnored
    var onRefreshRateChange: ((RefreshRate) -> Void)?

    var formatter: MetricFormatter {
        MetricFormatter(byteUnitSystem: byteUnitSystem, temperatureUnit: temperatureUnit)
    }

    var cadencePolicy: CadencePolicy {
        CadencePolicy(refreshRate: refreshRate)
    }

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginService: any LaunchAtLoginService = LiveLaunchAtLoginService()
    ) {
        self.defaults = defaults
        self.launchAtLoginService = launchAtLoginService
        appearance = Self.loadAppearance(from: defaults)
        refreshRate = Self.loadRefreshRate(from: defaults)
        byteUnitSystem = Self.loadByteUnitSystem(from: defaults)
        temperatureUnit = Self.loadTemperatureUnit(from: defaults)
        launchAtLoginStatus = launchAtLoginService.currentStatus()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginService.currentStatus()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try launchAtLoginService.register()
            } else {
                try launchAtLoginService.unregister()
            }
            launchAtLoginStatus = launchAtLoginService.currentStatus()
        } catch {
            launchAtLoginStatus = .failed(error.localizedDescription)
        }
    }

    private enum Keys {
        static let appearance = "settings.appearance"
        static let refreshRate = "settings.refreshRate"
        static let byteUnitSystem = "settings.byteUnitSystem"
        static let temperatureUnit = "settings.temperatureUnit"
    }

    private static func loadAppearance(from defaults: UserDefaults) -> AppAppearance {
        guard let raw = defaults.string(forKey: Keys.appearance), let value = AppAppearance(rawValue: raw) else {
            return .system
        }
        return value
    }

    private static func loadRefreshRate(from defaults: UserDefaults) -> RefreshRate {
        guard defaults.object(forKey: Keys.refreshRate) != nil else { return .oneSecond }
        return RefreshRate(rawValue: defaults.integer(forKey: Keys.refreshRate)) ?? .oneSecond
    }

    private static func loadByteUnitSystem(from defaults: UserDefaults) -> ByteUnitSystem {
        guard let raw = defaults.string(forKey: Keys.byteUnitSystem), let value = ByteUnitSystem(rawValue: raw) else {
            return .decimal
        }
        return value
    }

    private static func loadTemperatureUnit(from defaults: UserDefaults) -> TemperatureUnit {
        guard let raw = defaults.string(forKey: Keys.temperatureUnit), let value = TemperatureUnit(rawValue: raw) else {
            return .celsius
        }
        return value
    }
}

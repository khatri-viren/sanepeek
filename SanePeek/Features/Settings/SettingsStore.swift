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

    // Which metrics show a live status item and in which form. Only `.cpu` is enabled out of the
    // box, matching how most menu bar system monitors ship — everything else is opt-in. These
    // remain independent stored properties rather than one dictionary so `@Observable` can track
    // each metric preference precisely; `menuBarConfig(for:)` and `setMenuBarConfig(_:for:)`
    // preserve a single `MetricKind`-based access point for callers.
    var cpuMenuBarConfig: MenuBarMetricConfig {
        didSet {
            guard cpuMenuBarConfig != oldValue else { return }
            persistMenuBarConfig()
            onMenuBarConfigChange?()
        }
    }

    var memoryMenuBarConfig: MenuBarMetricConfig {
        didSet {
            guard memoryMenuBarConfig != oldValue else { return }
            persistMenuBarConfig()
            onMenuBarConfigChange?()
        }
    }

    var storageMenuBarConfig: MenuBarMetricConfig {
        didSet {
            guard storageMenuBarConfig != oldValue else { return }
            persistMenuBarConfig()
            onMenuBarConfigChange?()
        }
    }

    var networkMenuBarConfig: MenuBarMetricConfig {
        didSet {
            guard networkMenuBarConfig != oldValue else { return }
            persistMenuBarConfig()
            onMenuBarConfigChange?()
        }
    }

    var batteryMenuBarConfig: MenuBarMetricConfig {
        didSet {
            guard batteryMenuBarConfig != oldValue else { return }
            persistMenuBarConfig()
            onMenuBarConfigChange?()
        }
    }

    var gpuMenuBarConfig: MenuBarMetricConfig {
        didSet {
            guard gpuMenuBarConfig != oldValue else { return }
            persistMenuBarConfig()
            onMenuBarConfigChange?()
        }
    }

    var temperatureMenuBarConfig: MenuBarMetricConfig {
        didSet {
            guard temperatureMenuBarConfig != oldValue else { return }
            persistMenuBarConfig()
            onMenuBarConfigChange?()
        }
    }

    private(set) var launchAtLoginStatus: LaunchAtLoginStatus

    /// Set by `AppState` to route cadence changes into the live `MetricsEngine`.
    @ObservationIgnored
    var onRefreshRateChange: ((RefreshRate) -> Void)?

    /// Set by `AppState` to recompute which metrics the live `MetricsEngine` should be
    /// reading whenever the menu bar's enabled set or display modes change.
    @ObservationIgnored
    var onMenuBarConfigChange: (() -> Void)?

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
        let decodedMenuBarConfig = Self.loadMenuBarConfig(from: defaults)
        cpuMenuBarConfig = decodedMenuBarConfig[.cpu] ?? Self.defaultMenuBarConfig(for: .cpu)
        memoryMenuBarConfig = decodedMenuBarConfig[.memory] ?? Self.defaultMenuBarConfig(for: .memory)
        storageMenuBarConfig = decodedMenuBarConfig[.storage] ?? Self.defaultMenuBarConfig(for: .storage)
        networkMenuBarConfig = decodedMenuBarConfig[.network] ?? Self.defaultMenuBarConfig(for: .network)
        batteryMenuBarConfig = decodedMenuBarConfig[.battery] ?? Self.defaultMenuBarConfig(for: .battery)
        gpuMenuBarConfig = decodedMenuBarConfig[.gpu] ?? Self.defaultMenuBarConfig(for: .gpu)
        temperatureMenuBarConfig = decodedMenuBarConfig[.temperature] ?? Self.defaultMenuBarConfig(for: .temperature)
        launchAtLoginStatus = launchAtLoginService.currentStatus()
    }

    func menuBarConfig(for kind: MetricKind) -> MenuBarMetricConfig {
        switch kind {
        case .cpu: cpuMenuBarConfig
        case .memory: memoryMenuBarConfig
        case .storage: storageMenuBarConfig
        case .network: networkMenuBarConfig
        case .battery: batteryMenuBarConfig
        case .gpu: gpuMenuBarConfig
        case .temperature: temperatureMenuBarConfig
        }
    }

    func setMenuBarConfig(_ config: MenuBarMetricConfig, for kind: MetricKind) {
        switch kind {
        case .cpu: cpuMenuBarConfig = config
        case .memory: memoryMenuBarConfig = config
        case .storage: storageMenuBarConfig = config
        case .network: networkMenuBarConfig = config
        case .battery: batteryMenuBarConfig = config
        case .gpu: gpuMenuBarConfig = config
        case .temperature: temperatureMenuBarConfig = config
        }
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
        static let menuBarConfig = "settings.menuBarConfig"
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

    private static func defaultMenuBarConfig(for kind: MetricKind) -> MenuBarMetricConfig {
        MenuBarMetricConfig(isEnabled: kind == .cpu, displayMode: .number)
    }

    private static func loadMenuBarConfig(from defaults: UserDefaults) -> [MetricKind: MenuBarMetricConfig] {
        guard let data = defaults.data(forKey: Keys.menuBarConfig),
              let decoded = try? JSONDecoder().decode([MetricKind: MenuBarMetricConfig].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func persistMenuBarConfig() {
        let all: [MetricKind: MenuBarMetricConfig] = [
            .cpu: cpuMenuBarConfig,
            .memory: memoryMenuBarConfig,
            .storage: storageMenuBarConfig,
            .network: networkMenuBarConfig,
            .battery: batteryMenuBarConfig,
            .gpu: gpuMenuBarConfig,
            .temperature: temperatureMenuBarConfig
        ]
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Keys.menuBarConfig)
        }
    }
}

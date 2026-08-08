import SwiftUI

/// Maps domain snapshots to presentation-ready `MetricCardModel`s.
///
/// Warning/critical thresholds below are a presentation-layer decision: the PRD
/// specifies the warning/critical *colors* but gives no numeric cutoffs for
/// CPU, storage, network, battery, or GPU. Memory is the one exception — its
/// status comes directly from the OS-driven `MemoryPressure` state. Network
/// and GPU have no natural threshold signal, so they never show a status.
///
/// Every function takes a `MetricFormatter`, defaulted to decimal/Celsius, so
/// a future unit-preference setting (Phase 6) can be threaded through without
/// changing this mapping layer again.
nonisolated enum MetricCardMapping {
    private static let cpuWarningFraction = 0.80
    private static let cpuCriticalFraction = 0.95
    private static let storageWarningFraction = 0.85
    private static let storageCriticalFraction = 0.95
    private static let batteryWarningFraction = 0.20
    private static let batteryCriticalFraction = 0.10
    private static let temperatureWarningCelsius = 80.0
    private static let temperatureCriticalCelsius = 95.0
    /// Temperature has no natural 0...1 scale, so its `levelFraction` fills against the
    /// same displayed range `TemperatureGaugeView`'s dial sweeps, keeping the menu bar bar
    /// and the dashboard gauge in agreement about what "full" means.
    private static let temperatureScaleMinCelsius = 30.0
    private static let temperatureScaleMaxCelsius = 105.0

    static func cpuCard(
        _ snapshot: CPUSnapshot?,
        history: [Double],
        formatter: MetricFormatter = MetricFormatter()
    ) -> MetricCardModel {
        let title = "CPU"
        guard let snapshot, snapshot.availability.isAvailable else {
            return unavailableCard(id: .cpu, title: title, systemImage: "cpu", color: MetricPalette.cpu, availability: snapshot?.availability)
        }

        let status: MetricCardStatus? = snapshot.utilization.map { utilization in
            if utilization >= cpuCriticalFraction { return .critical }
            if utilization >= cpuWarningFraction { return .warning }
            return .normal
        }

        let primary = formatter.percentage(snapshot.utilization)
        let secondary = coreCountText(snapshot)

        return MetricCardModel(
            id: .cpu,
            title: title,
            systemImage: "cpu",
            accentColor: MetricPalette.cpu,
            primaryValue: primary,
            secondaryValue: secondary,
            status: status,
            unavailableMessage: nil,
            sparklineValues: history,
            levelFraction: snapshot.utilization,
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: primary, secondary: secondary, status: status)
        )
    }

    /// Nil when the breakdown can't be computed (snapshot missing, unavailable,
    /// or the first sample before a user/system delta exists) — `CPUCardView`
    /// falls back to placeholder text and an empty chart in that case.
    static func cpuDetail(
        _ snapshot: CPUSnapshot?,
        userHistory: [Double],
        systemHistory: [Double],
        formatter: MetricFormatter = MetricFormatter()
    ) -> CPUCardDetail? {
        guard let snapshot, snapshot.availability.isAvailable,
              let user = snapshot.userUtilization,
              let system = snapshot.systemUtilization
        else {
            return nil
        }

        let idle = max(0, 1 - user - system)
        return CPUCardDetail(
            chipName: snapshot.chipName,
            userPercentageText: formatter.percentage(user),
            systemPercentageText: formatter.percentage(system),
            idlePercentageText: formatter.percentage(idle),
            userHistory: userHistory,
            systemHistory: systemHistory
        )
    }

    static func memoryCard(
        _ snapshot: MemorySnapshot?,
        history: [Double],
        formatter: MetricFormatter = MetricFormatter()
    ) -> MetricCardModel {
        let title = "Memory"
        guard let snapshot, snapshot.availability.isAvailable else {
            return unavailableCard(id: .memory, title: title, systemImage: "memorychip", color: MetricPalette.memory, availability: snapshot?.availability)
        }

        let status: MetricCardStatus? = snapshot.pressure.map { pressure in
            switch pressure {
            case .normal: .normal
            case .warning: .warning
            case .critical: .critical
            }
        }

        let usedFraction: Double? = {
            guard let used = snapshot.usedBytes, let available = snapshot.availableBytes,
                  used + available > 0
            else {
                return nil
            }
            return Double(used) / Double(used + available)
        }()

        let primary = formatter.percentage(usedFraction)
        let secondary = snapshot.availableBytes.map { "\(formatter.bytes($0)) available" }

        return MetricCardModel(
            id: .memory,
            title: title,
            systemImage: "memorychip",
            accentColor: MetricPalette.memory,
            primaryValue: primary,
            secondaryValue: secondary,
            status: status,
            unavailableMessage: nil,
            sparklineValues: history,
            levelFraction: usedFraction,
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: primary, secondary: secondary, status: status)
        )
    }

    /// Nil when the breakdown can't be computed (snapshot missing, unavailable, or the
    /// App/Wired/Compressed fractions aren't available) — `MemoryCardView` falls back to
    /// placeholder text and an empty chart in that case.
    static func memoryDetail(
        _ snapshot: MemorySnapshot?,
        appHistory: [Double],
        wiredHistory: [Double],
        compressedHistory: [Double],
        formatter: MetricFormatter = MetricFormatter()
    ) -> MemoryCardDetail? {
        guard let snapshot, snapshot.availability.isAvailable,
              let used = snapshot.usedBytes,
              let available = snapshot.availableBytes,
              let app = snapshot.appUtilization,
              let wired = snapshot.wiredUtilization,
              let compressed = snapshot.compressedUtilization
        else {
            return nil
        }

        let free = max(0, 1 - app - wired - compressed)
        let totalBytes = used + available

        return MemoryCardDetail(
            totalRAMText: formatter.bytes(totalBytes),
            appPercentageText: formatter.percentage(app),
            wiredPercentageText: formatter.percentage(wired),
            compressedPercentageText: formatter.percentage(compressed),
            freePercentageText: formatter.percentage(free),
            appHistory: appHistory,
            wiredHistory: wiredHistory,
            compressedHistory: compressedHistory
        )
    }

    static func storageCard(
        _ snapshot: StorageSnapshot?,
        formatter: MetricFormatter = MetricFormatter()
    ) -> MetricCardModel {
        let title = "Storage"
        guard let snapshot, snapshot.availability.isAvailable else {
            return unavailableCard(id: .storage, title: title, systemImage: "internaldrive", color: MetricPalette.storage, availability: snapshot?.availability)
        }

        let usageFraction: Double? = {
            guard let used = snapshot.usedBytes, let total = snapshot.totalBytes, total > 0 else { return nil }
            return Double(used) / Double(total)
        }()

        let status: MetricCardStatus? = usageFraction.map { fraction in
            if fraction >= storageCriticalFraction { return .critical }
            if fraction >= storageWarningFraction { return .warning }
            return .normal
        }

        let primary = formatter.bytes(snapshot.usedBytes)
        let secondary: String? = {
            if let available = snapshot.availableBytes, let total = snapshot.totalBytes {
                return "\(formatter.bytes(available)) free of \(formatter.bytes(total))"
            } else if let available = snapshot.availableBytes {
                return "\(formatter.bytes(available)) free"
            }
            return nil
        }()
        let usageDetail: StorageUsageDetail? = {
            guard let used = snapshot.usedBytes, let available = snapshot.availableBytes, let total = snapshot.totalBytes else {
                return nil
            }
            return StorageUsageDetail(
                totalText: formatter.bytes(total),
                usedText: formatter.bytes(used),
                freeText: formatter.bytes(available)
            )
        }()

        return MetricCardModel(
            id: .storage,
            title: title,
            systemImage: "internaldrive",
            accentColor: MetricPalette.storage,
            primaryValue: primary,
            secondaryValue: secondary,
            status: status,
            unavailableMessage: nil,
            sparklineValues: [],
            levelFraction: usageFraction,
            usageFraction: usageFraction,
            storageUsageDetail: usageDetail,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: primary, secondary: secondary, status: status)
        )
    }

    static func networkCard(
        _ snapshot: NetworkSnapshot?,
        history: [Double],
        formatter: MetricFormatter = MetricFormatter()
    ) -> MetricCardModel {
        let title = "Network"
        guard let snapshot, snapshot.availability.isAvailable else {
            return unavailableCard(id: .network, title: title, systemImage: "network", color: MetricPalette.network, availability: snapshot?.availability)
        }

        let primary = throughputText(snapshot.downloadBytesPerSecond, formatter: formatter)
        let secondary = snapshot.uploadBytesPerSecond.map { "\u{2191} \(throughputText($0, formatter: formatter))" }

        // Network is the one metric with no absolute ceiling to fill against — link
        // capacity isn't knowable — so its level is scaled to the trailing window's own
        // peak, the same self-scaling the menu bar's chart used. A full bar therefore
        // means "the busiest this minute has been", not "saturated".
        let levelFraction: Double? = {
            guard let current = snapshot.downloadBytesPerSecond, current.isFinite, current >= 0 else { return nil }
            let peak = max(history.max() ?? 0, current)
            guard peak > 0 else { return 0 }
            return current / peak
        }()

        return MetricCardModel(
            id: .network,
            title: title,
            systemImage: "network",
            accentColor: MetricPalette.network,
            primaryValue: primary,
            secondaryValue: secondary,
            status: nil,
            unavailableMessage: nil,
            sparklineValues: history,
            levelFraction: levelFraction,
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: "Download \(primary)", secondary: secondary, status: nil)
        )
    }

    /// Nil when the snapshot is missing/unavailable — `NetworkCardView` falls back to
    /// placeholder text and an empty chart in that case, matching `temperatureDetail`.
    static func networkDetail(
        _ snapshot: NetworkSnapshot?,
        downloadHistory: [Double],
        uploadHistory: [Double],
        formatter: MetricFormatter = MetricFormatter()
    ) -> NetworkCardDetail? {
        guard let snapshot, snapshot.availability.isAvailable else { return nil }
        return NetworkCardDetail(
            subtitleText: networkSubtitleText(snapshot),
            downloadText: throughputText(snapshot.downloadBytesPerSecond, formatter: formatter),
            uploadText: snapshot.uploadBytesPerSecond.map { throughputText($0, formatter: formatter) },
            downloadHistory: downloadHistory,
            uploadHistory: uploadHistory
        )
    }

    static func batteryCard(
        _ snapshot: BatterySnapshot?,
        formatter: MetricFormatter = MetricFormatter()
    ) -> MetricCardModel {
        let title = "Battery"
        guard let snapshot, snapshot.availability.isAvailable else {
            return unavailableCard(id: .battery, title: title, systemImage: "battery.100", color: MetricPalette.battery, availability: snapshot?.availability)
        }

        let status: MetricCardStatus? = snapshot.percentage.map { percentage in
            guard snapshot.chargingState == .unplugged else { return .normal }
            if percentage <= batteryCriticalFraction { return .critical }
            if percentage <= batteryWarningFraction { return .warning }
            return .normal
        }

        let primary = formatter.percentage(snapshot.percentage)
        let secondary = batterySecondary(snapshot, formatter: formatter)

        return MetricCardModel(
            id: .battery,
            title: title,
            systemImage: "battery.100",
            accentColor: MetricPalette.battery,
            primaryValue: primary,
            secondaryValue: secondary,
            status: status,
            unavailableMessage: nil,
            sparklineValues: [],
            levelFraction: snapshot.percentage,
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: primary, secondary: secondary, status: status)
        )
    }

    /// Returns nil to hide the card entirely when utilization cannot be reliably
    /// read, rather than showing misleading data.
    static func gpuCard(
        _ snapshot: GPUSnapshot?,
        history: [Double],
        formatter: MetricFormatter = MetricFormatter()
    ) -> MetricCardModel? {
        guard let snapshot, snapshot.availability.isAvailable, let utilization = snapshot.utilization else {
            return nil
        }

        let title = "GPU"
        let primary = formatter.percentage(utilization)

        return MetricCardModel(
            id: .gpu,
            title: title,
            systemImage: "gearshape.2",
            accentColor: MetricPalette.gpu,
            primaryValue: primary,
            secondaryValue: snapshot.name,
            status: nil,
            unavailableMessage: nil,
            sparklineValues: history,
            levelFraction: utilization,
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: primary, secondary: snapshot.name, status: nil)
        )
    }

    static func temperatureCard(
        _ snapshot: TemperatureSnapshot?,
        history: [Double],
        formatter: MetricFormatter = MetricFormatter()
    ) -> MetricCardModel {
        let title = "Temperature"
        guard let snapshot, snapshot.availability.isAvailable else {
            return unavailableCard(id: .temperature, title: title, systemImage: "thermometer.medium", color: MetricPalette.temperature, availability: snapshot?.availability)
        }

        let hottest = [snapshot.cpuCelsius, snapshot.gpuCelsius].compactMap { $0 }.max()
        let status: MetricCardStatus? = hottest.map { value in
            if value >= temperatureCriticalCelsius { return .critical }
            if value >= temperatureWarningCelsius { return .warning }
            return .normal
        }

        let primary = formatter.temperature(hottest)
        let secondary = [
            snapshot.cpuCelsius.map { "CPU \(formatter.temperature($0))" },
            snapshot.gpuCelsius.map { "GPU \(formatter.temperature($0))" }
        ].compactMap { $0 }.joined(separator: " \u{00B7} ")

        return MetricCardModel(
            id: .temperature,
            title: title,
            systemImage: "thermometer.medium",
            accentColor: MetricPalette.temperature,
            primaryValue: primary,
            secondaryValue: secondary.isEmpty ? nil : secondary,
            status: status,
            unavailableMessage: nil,
            sparklineValues: history,
            levelFraction: hottest.map(temperatureLevelFraction),
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: primary, secondary: secondary.isEmpty ? nil : secondary, status: status)
        )
    }

    /// Nil when the snapshot is unavailable — `TemperatureCardView` falls back to
    /// placeholder text and an empty chart in that case, matching `cpuDetail`/`memoryDetail`.
    static func temperatureDetail(
        _ snapshot: TemperatureSnapshot?,
        formatter: MetricFormatter = MetricFormatter()
    ) -> TemperatureCardDetail? {
        guard let snapshot, snapshot.availability.isAvailable else { return nil }
        let hottest = [snapshot.cpuCelsius, snapshot.gpuCelsius].compactMap { $0 }.max()
        return TemperatureCardDetail(
            hottestCelsius: hottest,
            hottestText: formatter.temperature(hottest),
            cpuText: snapshot.cpuCelsius.map { formatter.temperature($0) },
            gpuText: snapshot.gpuCelsius.map { formatter.temperature($0) }
        )
    }

    private static func unavailableCard(
        id: MetricKind,
        title: String,
        systemImage: String,
        color: Color,
        availability: MetricAvailability?
    ) -> MetricCardModel {
        let message = availability?.userMessage ?? MetricUnavailableReason.noData.userMessage
        return MetricCardModel(
            id: id,
            title: title,
            systemImage: systemImage,
            accentColor: color,
            primaryValue: "--",
            secondaryValue: nil,
            status: nil,
            unavailableMessage: message,
            sparklineValues: [],
            levelFraction: nil,
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: message
        )
    }

    /// Clamped to the gauge's displayed range so a reading past either end pins the bar
    /// full/empty rather than overflowing it.
    private static func temperatureLevelFraction(_ celsius: Double) -> Double {
        let clamped = min(max(celsius, temperatureScaleMinCelsius), temperatureScaleMaxCelsius)
        return (clamped - temperatureScaleMinCelsius) / (temperatureScaleMaxCelsius - temperatureScaleMinCelsius)
    }

    private static func accessibilityValue(primary: String, secondary: String?, status: MetricCardStatus?) -> String {
        var parts = [primary]
        if let secondary { parts.append(secondary) }
        if let word = status?.accessibilityWord { parts.append(word) }
        return parts.joined(separator: ", ")
    }

    private static func coreCountText(_ snapshot: CPUSnapshot) -> String? {
        if let performance = snapshot.performanceCoreCount, let efficiency = snapshot.efficiencyCoreCount {
            return "\(performance)P + \(efficiency)E cores"
        } else if let cores = snapshot.logicalCoreCount {
            return "\(cores) cores"
        }
        return nil
    }

    private static func throughputText(_ bytesPerSecond: Double?, formatter: MetricFormatter) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "Unavailable" }
        return "\(formatter.bytes(UInt64(bytesPerSecond)))/s"
    }

    /// `snapshot.interfaceNames` lists every "up" non-loopback interface, which
    /// on a real Mac includes VPN tunnels, AirDrop/Continuity virtual
    /// interfaces, and Internet Sharing bridges alongside the one actually
    /// carrying traffic — not what "what am I connected through" should show.
    /// `primaryInterfaceName` (from SystemConfiguration's default-route lookup)
    /// is the single real answer; fall back to a connectivity word if there's
    /// no default route.
    private static func networkSubtitleText(_ snapshot: NetworkSnapshot) -> String? {
        if let primary = snapshot.primaryInterfaceName, !primary.isEmpty {
            return primary
        }
        return snapshot.connectivity.map { connectivityText($0) }
    }

    private static func connectivityText(_ connectivity: NetworkConnectivity) -> String {
        switch connectivity {
        case .connected: "Connected"
        case .disconnected: "Not connected"
        case .unknown: "Unknown"
        }
    }

    private static func batterySecondary(_ snapshot: BatterySnapshot, formatter: MetricFormatter) -> String? {
        var parts: [String] = []
        if let state = snapshot.chargingState {
            parts.append(chargingStateText(state))
        }
        if let remaining = snapshot.timeRemaining, snapshot.chargingState != .charged {
            parts.append("\(formatter.duration(remaining)) left")
        }
        if let health = snapshot.healthPercentage {
            parts.append("\(formatter.percentage(health)) health")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private static func chargingStateText(_ state: BatteryChargingState) -> String {
        switch state {
        case .charging: "Charging"
        case .charged: "Charged"
        case .unplugged: "On battery"
        case .unknown: "Unknown state"
        }
    }
}

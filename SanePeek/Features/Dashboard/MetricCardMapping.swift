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
            usageFraction: usageFraction,
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
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: "Download \(primary)", secondary: secondary, status: nil)
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
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue(primary: primary, secondary: snapshot.name, status: nil)
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
            usageFraction: nil,
            accessibilityLabel: title,
            accessibilityValue: message
        )
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

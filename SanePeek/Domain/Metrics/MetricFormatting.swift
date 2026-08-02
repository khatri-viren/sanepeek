import Foundation

nonisolated enum ByteUnitSystem: String, CaseIterable, Equatable, Sendable {
    case decimal
    case binary

    var base: Double {
        switch self {
        case .decimal:
            1_000
        case .binary:
            1_024
        }
    }

    var symbols: [String] {
        switch self {
        case .decimal:
            ["B", "kB", "MB", "GB", "TB"]
        case .binary:
            ["B", "KiB", "MiB", "GiB", "TiB"]
        }
    }
}

nonisolated enum TemperatureUnit: String, CaseIterable, Equatable, Sendable {
    case celsius
    case fahrenheit
}

nonisolated struct MetricFormatter: Sendable, Equatable {
    let byteUnitSystem: ByteUnitSystem
    let temperatureUnit: TemperatureUnit

    init(
        byteUnitSystem: ByteUnitSystem = .decimal,
        temperatureUnit: TemperatureUnit = .celsius
    ) {
        self.byteUnitSystem = byteUnitSystem
        self.temperatureUnit = temperatureUnit
    }

    func bytes(_ value: UInt64?) -> String {
        guard let value else {
            return "Unavailable"
        }

        var scaled = Double(value)
        var symbolIndex = 0
        let symbols = byteUnitSystem.symbols

        while scaled >= byteUnitSystem.base, symbolIndex < symbols.count - 1 {
            scaled /= byteUnitSystem.base
            symbolIndex += 1
        }

        let fractionDigits: Int
        if symbolIndex == 0 || scaled >= 100 {
            fractionDigits = 0
        } else if scaled >= 10 {
            fractionDigits = 1
        } else {
            fractionDigits = 2
        }

        return "\(Self.number(scaled, maximumFractionDigits: fractionDigits)) \(symbols[symbolIndex])"
    }

    func bytes(_ result: MetricResult<UInt64>) -> String {
        switch result {
        case let .available(value):
            bytes(value)
        case .unavailable, .failed:
            unavailableText(for: result.availability)
        }
    }

    func percentage(_ fraction: Double?, fractionDigits: Int = 0) -> String {
        guard let fraction, fraction.isFinite else {
            return "Unavailable"
        }

        let clampedFraction = min(max(fraction, 0), 1)
        let value = clampedFraction * 100
        return "\(Self.number(value, maximumFractionDigits: fractionDigits))%"
    }

    func percentage(_ result: MetricResult<Double>, fractionDigits: Int = 0) -> String {
        switch result {
        case let .available(value):
            percentage(value, fractionDigits: fractionDigits)
        case .unavailable, .failed:
            unavailableText(for: result.availability)
        }
    }

    func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds,
              seconds.isFinite,
              seconds >= 0,
              seconds <= Double(Int.max)
        else {
            return "Unavailable"
        }

        var remaining = Int(seconds.rounded(.down))
        if remaining < 60 {
            return "\(remaining)s"
        }

        let days = remaining / 86_400
        remaining %= 86_400
        let hours = remaining / 3_600
        remaining %= 3_600
        let minutes = remaining / 60
        let remainderSeconds = remaining % 60
        var components: [String] = []

        if days > 0 {
            components.append("\(days)d")
        }
        if hours > 0 {
            components.append("\(hours)h")
        }
        if minutes > 0 {
            components.append("\(minutes)m")
        }
        if components.isEmpty || (components.count == 1 && remainderSeconds > 0) {
            components.append("\(remainderSeconds)s")
        }

        return components.prefix(2).joined(separator: " ")
    }

    func duration(_ result: MetricResult<Double>) -> String {
        switch result {
        case let .available(value):
            duration(value)
        case .unavailable, .failed:
            unavailableText(for: result.availability)
        }
    }

    func temperature(_ celsius: Double?, fractionDigits: Int = 1) -> String {
        guard let celsius, celsius.isFinite else {
            return "Unavailable"
        }

        let value: Double
        let symbol: String
        switch temperatureUnit {
        case .celsius:
            value = celsius
            symbol = "°C"
        case .fahrenheit:
            value = (celsius * 9 / 5) + 32
            symbol = "°F"
        }

        return "\(Self.number(value, maximumFractionDigits: fractionDigits)) \(symbol)"
    }

    func temperature(_ result: MetricResult<Double>, fractionDigits: Int = 1) -> String {
        switch result {
        case let .available(value):
            temperature(value, fractionDigits: fractionDigits)
        case .unavailable, .failed:
            unavailableText(for: result.availability)
        }
    }

    private func unavailableText(for availability: MetricAvailability) -> String {
        availability.userMessage ?? "Unavailable"
    }

    private static func number(
        _ value: Double,
        maximumFractionDigits: Int,
        minimumFractionDigits: Int = 0
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = max(minimumFractionDigits, 0)
        formatter.maximumFractionDigits = min(max(maximumFractionDigits, 0), 6)
        return formatter.string(from: NSNumber(value: value)) ?? "Unavailable"
    }
}

import Foundation

extension Formatter {
    static let iso8601withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let decimalFormatterWithTwoFractionDigits: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let decimalFormatterWithThreeFractionDigits: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        return dateFormatter
    }()

    static let decimalFormatterWithOneFractionDigit: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static let bolusFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.minimumIntegerDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

extension Duration {
    /// Minutes as overrides and temp targets store them. Clamped because those values come from
    /// Core Data and Nightscout unchecked, and NaN or 1e30 would trap; Int32.max minutes is ~4,000 years.
    init(minutes: Decimal) {
        let minutes = Double(minutes)
        self = minutes.isNaN ? .zero : .seconds(min(max(minutes, 0), Double(Int32.max)) * 60)
    }

    /// Compact span, rounded down: "45m", "1h 30m", "5d 14h", "< 1m".
    func formattedTimeSpan(locale: Locale = .autoupdatingCurrent) -> String {
        timeSpan(width: .narrow, locale: locale)
    }

    /// VoiceOver form of `formattedTimeSpan`: "1 hour, 30 minutes".
    func formattedSpokenTimeSpan(locale: Locale = .autoupdatingCurrent) -> String {
        timeSpan(width: .wide, locale: locale)
    }

    private func timeSpan(width: UnitsFormatStyle.UnitWidth, locale: Locale) -> String {
        // Zero is an exact length, like an unset duration picker, not "less than a minute".
        if self < .seconds(60), self != .zero {
            return "<\u{00A0}" + Duration.seconds(60).timeSpan(width: width, locale: locale)
        }
        let units: Set<UnitsFormatStyle.Unit> = self < .seconds(86400) ? [.hours, .minutes] : [.days, .hours]
        return formatted(.units(allowed: units, width: width, fractionalPart: .hide(rounded: .down)).locale(locale))
    }
}

extension Date {
    /// Time since this date, rounded down: "7m", "1h 30m", "< 1m".
    func formattedTimeAgo(locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(-timeIntervalSinceNow).formattedTimeSpan(locale: locale)
    }

    /// VoiceOver: "7 minutes ago", "1 hour ago", "yesterday", "less than a minute ago".
    func formattedSpokenTimeAgo(locale: Locale = .autoupdatingCurrent) -> String {
        let elapsed = -timeIntervalSinceNow
        guard elapsed >= 60 else {
            return String(localized: "less than a minute ago", comment: "Accessibility: elapsed time")
        }
        // Under a day the style rounds to the nearest minute or hour; floor so VoiceOver matches the visible text.
        // From a day on it counts calendar days ("yesterday"); shifting the date could cross midnight.
        let remainder: TimeInterval = switch elapsed {
        case ..<3600: elapsed.truncatingRemainder(dividingBy: 60)
        case ..<86400: elapsed.truncatingRemainder(dividingBy: 3600)
        default: 0
        }
        return addingTimeInterval(remainder).formatted(.relative(presentation: .named, unitsStyle: .wide).locale(locale))
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static let customISO8601 = custom {
        let container = try $0.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = Formatter.iso8601withFractionalSeconds.date(from: string) ?? Formatter.iso8601.date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
    }
}

extension JSONEncoder.DateEncodingStrategy {
    static let customISO8601 = custom {
        var container = $1.singleValueContainer()
        try container.encode(Formatter.iso8601withFractionalSeconds.string(from: $0))
    }
}

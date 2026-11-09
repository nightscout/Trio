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

    /// Which units a span shows. All round down.
    enum SpanStyle {
        /// Days, hours and minutes, for stored values: "1d 1h 30m".
        case exact
        /// Hours and minutes under a day, days and hours from a day on, for countdowns and ages: "2d 16h".
        case largestTwoUnits
        /// Minutes only, for settings counted in minutes: "90m".
        case minutes
    }

    /// Compact span, rounded down: "45m", "1h 30m", "5d 14h", "< 1m".
    func formattedTimeSpan(_ style: SpanStyle = .exact, locale: Locale = .autoupdatingCurrent) -> String {
        if isUnderAMinute {
            return "<\u{00A0}" + Duration.seconds(60).timeSpan(style, width: .narrow, locale: locale)
        }
        return timeSpan(style, width: .narrow, locale: locale)
    }

    /// VoiceOver form of `formattedTimeSpan`: "1 hour, 30 minutes", "less than a minute".
    /// `locale` formats the units; "less than a minute" follows the app language.
    func formattedSpokenTimeSpan(_ style: SpanStyle = .exact, locale: Locale = .autoupdatingCurrent) -> String {
        if isUnderAMinute {
            return String(localized: "less than a minute", comment: "Accessibility: a duration under one minute")
        }
        return timeSpan(style, width: .wide, locale: locale)
    }

    /// Zero is an exact length, like an unset duration picker, so it stays "0m" rather than "< 1m".
    var isUnderAMinute: Bool { self < .seconds(60) && self != .zero }

    private func timeSpan(_ style: SpanStyle, width: UnitsFormatStyle.UnitWidth, locale: Locale) -> String {
        let units: Set<UnitsFormatStyle.Unit> = switch style {
        case .exact: [.days, .hours, .minutes]
        case .largestTwoUnits: self < .seconds(86400) ? [.hours, .minutes] : [.days, .hours]
        case .minutes: [.minutes]
        }
        return formatted(.units(allowed: units, width: width, fractionalPart: .hide(rounded: .down)).locale(locale))
    }
}

extension Date {
    /// Time since this date, rounded down: "7m", "1h 30m", "< 1m".
    func formattedTimeAgo(locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(-timeIntervalSinceNow).formattedTimeSpan(.largestTwoUnits, locale: locale)
    }

    /// VoiceOver form of `formattedTimeAgo`: "1 hour, 59 minutes ago", "less than a minute ago".
    /// `locale` formats the duration; the words around it follow the app language, like `String(localized:locale:)`.
    func formattedSpokenTimeAgo(locale: Locale = .autoupdatingCurrent) -> String {
        let elapsed = Duration.seconds(-timeIntervalSinceNow)
        // One phrase rather than span + "ago", so translators can get its grammar right.
        if elapsed.isUnderAMinute {
            return String(localized: "less than a minute ago", comment: "Accessibility: elapsed time")
        }

        return String(
            localized: "\(elapsed.formattedSpokenTimeSpan(.largestTwoUnits, locale: locale)) ago",
            comment: "Accessibility: elapsed time; %@ is a duration like \"1 hour, 59 minutes\". Word it so %@ stays unchanged (German: \"%@ her\")."
        )
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

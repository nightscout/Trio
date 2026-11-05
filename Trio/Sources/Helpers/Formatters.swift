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

    static let timaAgoFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.negativePrefix = ""
        return formatter
    }()
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

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Percent {
    /// No decimals: 0.8 → "80%".
    static var wholePercent: Self { roundedPercent(0 ... 0) }

    /// Exactly one decimal: 0.07 → "7.0%".
    static var oneDecimalPercent: Self { roundedPercent(1 ... 1) }

    /// Up to one decimal: 0.725 → "72.5%", 0.72 → "72%".
    static var upToOneDecimalPercent: Self { roundedPercent(0 ... 1) }

    /// Rounds halves away from zero, like glucose.
    private static func roundedPercent(_ fractionLength: ClosedRange<Int>) -> Self {
        .percent.precision(.fractionLength(fractionLength)).rounded(rule: .toNearestOrAwayFromZero)
    }
}

/// The same styles for Decimal values.
extension FormatStyle where Self == Decimal.FormatStyle.Percent {
    static var wholePercent: Self { roundedPercent(0 ... 0) }
    static var oneDecimalPercent: Self { roundedPercent(1 ... 1) }
    static var upToOneDecimalPercent: Self { roundedPercent(0 ... 1) }

    private static func roundedPercent(_ fractionLength: ClosedRange<Int>) -> Self {
        .percent.precision(.fractionLength(fractionLength)).rounded(rule: .toNearestOrAwayFromZero)
    }
}

import Foundation

extension Decimal {
    /// Converts a `Double` to a `Decimal` using JSON style conversion
    init(algorithmValue value: Double) {
        self = Decimal(string: value.description) ?? Decimal(value)
    }

    /// The nearest `Double`, via the decimal string — the inverse of `init(algorithmValue:)`.
    /// `Double(truncating:)` can land a hair below the value (0.07 becomes 0.06999999999999999),
    /// which a pump's floor-to-supported-rate lookup then drops a whole increment. The locale is
    /// pinned so a comma-decimal locale cannot break the parse.
    var nearestDouble: Double {
        var value = self
        return Double(NSDecimalString(&value, Locale(identifier: "en_US_POSIX")))
            ?? Double(truncating: self as NSNumber)
    }
}

extension Collection where Element == Decimal {
    /// Returns the arithmetic mean, or zero if empty.
    var mean: Decimal {
        guard !isEmpty else { return .zero }
        return reduce(.zero, +) / Decimal(count)
    }
}

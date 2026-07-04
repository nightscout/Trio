import Foundation

extension Decimal {
    func rounded(scale: Int, roundingMode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        let handler = NSDecimalNumberHandler(
            roundingMode: roundingMode,
            scale: Int16(scale),
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: self).rounding(accordingToBehavior: handler).decimalValue
    }

    func rounded() -> Decimal {
        rounded(scale: 0)
    }

    /// Implement Math.round from JS on Decimals. The JS implementation will add 0.5
    /// and do a floor operation, which is what we're doing here. This ends up mattering
    /// for values that are negative and end with .5 exactly
    func jsRounded(scale: Int) -> Decimal {
        var multiplier = (0 ..< scale).reduce(Decimal(1)) { result, _ in result * 10 }
        return (self * multiplier + 0.5).rounded(scale: 0, roundingMode: .down) / multiplier
    }

    // Implement Math.floor from JS on Decimals
    func floor() -> Decimal {
        rounded(scale: 0, roundingMode: .down)
    }

    func jsRounded() -> Decimal {
        // double rounding to help with imprecision in calculations
        jsRounded(scale: 6).jsRounded(scale: 0)
    }

    func clamp(lowerBound: Decimal, upperBound: Decimal) -> Decimal {
        if self < lowerBound {
            return lowerBound
        } else if self > upperBound {
            return upperBound
        } else {
            return self
        }
    }
}

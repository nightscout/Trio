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

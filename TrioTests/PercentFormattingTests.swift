import Foundation
import Testing

@testable import Trio

@Suite("Percent Formatting") struct PercentFormattingTests {
    private let english = Locale(identifier: "en_US")

    @Test("Whole percent rounds halves away from zero", arguments: [
        ("0.8", "80%"), ("0.725", "73%")
    ]) func whole(input: String, expected: String) {
        check(input, expected, double: .wholePercent, decimal: .wholePercent)
    }

    @Test("One decimal keeps a trailing zero and rounds halves away from zero", arguments: [
        ("0.07", "7.0%"), ("0.0125", "1.3%")
    ]) func oneDecimal(input: String, expected: String) {
        check(input, expected, double: .oneDecimalPercent, decimal: .oneDecimalPercent)
    }

    @Test("Up to one decimal drops a trailing zero, so exact shares stay short", arguments: [
        ("0", "0%"), ("1", "100%"), ("0.873", "87.3%")
    ]) func upToOneDecimal(input: String, expected: String) {
        check(input, expected, double: .upToOneDecimalPercent, decimal: .upToOneDecimalPercent)
    }

    @Test("Up to two decimals drops trailing zeros", arguments: [
        ("0.8333", "83.33%"), ("0.72", "72%")
    ]) func upToTwoDecimals(input: String, expected: String) {
        check(input, expected, double: .upToTwoDecimalPercent, decimal: .upToTwoDecimalPercent)
    }

    /// The Double and Decimal styles are separate copies, so both are checked.
    private func check(
        _ input: String,
        _ expected: String,
        double: FloatingPointFormatStyle<Double>.Percent,
        decimal: Decimal.FormatStyle.Percent
    ) {
        #expect(Double(input)!.formatted(double.locale(english)) == expected)
        #expect(Decimal(string: input)!.formatted(decimal.locale(english)) == expected)
    }
}

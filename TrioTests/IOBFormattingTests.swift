import Foundation
import Testing

@testable import Trio

/// Every case runs in English and French; locale should only swap the decimal point for a comma.
@Suite("IOB Formatting") struct IOBFormattingTests {
    private let english = Locale(identifier: "en_US")
    private let french = Locale(identifier: "fr_FR")

    @Test("Up to two decimals, halves away from zero, never -0", arguments: [
        (Decimal(2), "2"), (0.05, "0.05"), (1.234, "1.23"), (-0.25, "-0.25"),
        (0.125, "0.13"), (-0.125, "-0.13"), (-0.004, "0")
    ]) func iob(input: Decimal, expected: String) {
        #expect(input.formattedIOB(locale: english) == expected)
        #expect(input.formattedIOB(locale: french) == expected.replacing(".", with: ","))
    }
}

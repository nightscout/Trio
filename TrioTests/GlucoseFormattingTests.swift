import Foundation
import Testing

@testable import Trio

/// Every case runs in English and French; locale should only swap the decimal point for a comma.
@Suite("Glucose Formatting") struct GlucoseFormattingTests {
    private let english = Locale(identifier: "en_US")
    private let french = Locale(identifier: "fr_FR")

    @Test("mg/dL shows whole numbers and rounds halves away from zero", arguments: [
        (Decimal(120), "120"), (120.4, "120"), (120.5, "121")
    ]) func mgdL(input: Decimal, expected: String) {
        #expect(input.formatted(for: .mgdL, locale: english) == expected)
        #expect(input.formatted(for: .mgdL, locale: french) == expected)
    }

    @Test("mmol/L converts from mg/dL and always shows one decimal", arguments: [
        (Decimal(70), "3.9"), (108, "6.0"), (180, "10.0")
    ]) func mmolL(input: Decimal, expected: String) {
        #expect(input.formatted(for: .mmolL, locale: english) == expected)
        #expect(input.formatted(for: .mmolL, locale: french) == expected.replacing(".", with: ","))
    }

    @Test("Delta always shows its sign, including zero", arguments: [
        (Decimal(0), "+0.0"), (18, "+1.0"), (-9, "-0.5")
    ]) func delta(input: Decimal, expected: String) {
        #expect(input.formattedDelta(for: .mmolL, locale: english) == expected)
        #expect(input.formattedDelta(for: .mmolL, locale: french) == expected.replacing(".", with: ","))
    }

    @Test("ISF keeps its mg/dL decimal so the bolus math on screen adds up", arguments: [
        (Decimal(43.6), "43.6"), (44, "44")
    ]) func isf(input: Decimal, expected: String) {
        #expect(input.formattedISF(for: .mgdL, locale: english) == expected)
        #expect(input.formattedISF(for: .mgdL, locale: french) == expected.replacing(".", with: ","))
    }
}

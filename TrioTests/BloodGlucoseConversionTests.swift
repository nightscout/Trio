import Foundation
import Testing

@testable import Trio

/// Regression suite for the mg/dL ↔ mmol/L conversion utilities used by
/// `Decimal`, `Int`, and the Nightscout import path. The motivating cases
/// come from issue #1179 (mmol/L ISF imports drifting by ±0.1).
@Suite("Blood Glucose Conversion Tests") struct BloodGlucoseConversionTests {
    // Helper: construct a Decimal from a decimal string (avoids the float-literal
    // path that goes through Double and introduces precision noise like 5.55 ≈
    // 5.5499999999...). All test inputs that need exact decimal precision use this.
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: - asMgdLForImport

    /// `asMgdLForImport` is the import-boundary conversion that picks the
    /// integer mg/dL whose round-trip back to mmol/L matches the source's
    /// 1-decimal mmol/L display. Each case lists the mmol/L source value and
    /// the mmol/L display we expect to see after import→display.
    @Test("asMgdLForImport preserves the source's 1-decimal mmol/L display") func asMgdLForImport_preservesMmolLDisplay() {
        let cases: [(source: Decimal, expectedDisplay: Decimal)] = [
            // Exact, mid-band values — should round-trip cleanly.
            (d("5.5"), d("5.5")),
            (d("5.6"), d("5.6")),
            (d("5.7"), d("5.7")),
            (d("3.7"), d("3.7")),
            (d("3.8"), d("3.8")),
            (d("5.0"), d("5.0")),
            (d("10.0"), d("10.0")),
            (d("22.0"), d("22.0")),

            // Half-up boundary values — NS may emit these after its own
            // integer-mg/dL round-trip (e.g. user entered 5.6, NS stored 100,
            // NS re-emitted 100/18.0182 ≈ 5.55). Display should land on the
            // user-intended side.
            (d("5.55"), d("5.6")),
            (d("5.45"), d("5.5")),
            (d("3.65"), d("3.7")),
            (d("3.75"), d("3.8")),

            // Raw derived NS values (using NS's typical factor of 18) — same
            // integer mg/dL source, different mmol/L emission than Trio's
            // 18.0182. Display should match the user-intended value.
            (d("5.6111"), d("5.6")), // 101 / 18
            (d("3.7222"), d("3.7")) // 67 / 18
        ]

        for c in cases {
            let mgdL = c.source.asMgdLForImport
            #expect(
                mgdL.asMmolL == c.expectedDisplay,
                "source \(c.source) mmol/L → \(mgdL) mg/dL → \(mgdL.asMmolL) mmol/L (expected display \(c.expectedDisplay))"
            )
        }
    }

    /// Pre-existing `asMgdL` returns integer mg/dL via `scale: 0` rounding —
    /// `asMgdLForImport` must do the same (the picker dedup downstream
    /// assumes integer-spaced values).
    @Test("asMgdLForImport returns integer-valued mg/dL") func asMgdLForImport_returnsInteger() {
        let inputs: [Decimal] = [
            d("5.5"), d("5.55"), d("5.6"), d("5.65"), d("5.7"),
            d("3.7"), d("3.8"), d("10.0"), d("15.5")
        ]
        for input in inputs {
            let mgdL = input.asMgdLForImport
            let asInt = NSDecimalNumber(decimal: mgdL).intValue
            #expect(mgdL == Decimal(asInt), "asMgdLForImport(\(input)) must be integer-valued, got \(mgdL)")
        }
    }

    // MARK: - Direct conversion round-trips

    /// `Decimal.asMmolL` and `Decimal.asMgdL` operate on the *display* unit
    /// (mmol/L to 1 decimal, mg/dL to 0). For any integer mg/dL value, the
    /// mmol/L display we compute should be reproducible on a follow-up
    /// mg/dL→mmol/L→mg/dL→mmol/L pass.
    @Test("Integer mg/dL → mmol/L display is stable on re-conversion") func mgdLToMmolL_displayIsStable() {
        for mgdL in 40 ... 400 {
            let original = Decimal(mgdL)
            let firstMmol = original.asMmolL
            let bouncedMgdL = firstMmol.asMgdL
            let secondMmol = bouncedMgdL.asMmolL
            #expect(
                firstMmol == secondMmol,
                "Display drift at \(mgdL) mg/dL: first asMmolL = \(firstMmol), second = \(secondMmol)"
            )
        }
    }

    /// `Int.asMmolL` and `Decimal.asMmolL` should agree for integer inputs.
    @Test("Int.asMmolL agrees with Decimal.asMmolL") func intAndDecimalAsMmolL_agree() {
        for mgdL in 40 ... 400 {
            #expect(mgdL.asMmolL == Decimal(mgdL).asMmolL, "Disagreement at \(mgdL) mg/dL")
        }
    }

    // MARK: - Issue #1179 regression

    /// The original report: user has 5.6 mmol/L ISF in NS, Trio imports as
    /// 5.7 (dev's `correctUnitParsingOffsets` +1 hack) or 5.5 (post-PR
    /// without the import-boundary fix). Whatever NS emits — 5.6 exactly,
    /// 5.55 (its internal integer round-trip), or 5.6111 (raw 101/18) —
    /// the resulting Trio display must be 5.6.
    @Test("Issue #1179: 5.6 mmol/L ISF imports as 5.6 across NS emission variants") func issue1179_5_6() {
        for source in [d("5.6"), d("5.55"), d("5.6111")] {
            let mgdL = source.asMgdLForImport
            #expect(mgdL.asMmolL == d("5.6"), "NS source \(source) → \(mgdL) mg/dL → \(mgdL.asMmolL) mmol/L (expected 5.6)")
        }
    }

    /// Same story for the second value bjorn flagged.
    @Test("Issue #1179: 3.7 mmol/L ISF imports as 3.7 across NS emission variants") func issue1179_3_7() {
        for source in [d("3.7"), d("3.65"), d("3.7222")] {
            let mgdL = source.asMgdLForImport
            #expect(mgdL.asMmolL == d("3.7"), "NS source \(source) → \(mgdL) mg/dL → \(mgdL.asMmolL) mmol/L (expected 3.7)")
        }
    }

    /// Sweep the entire therapy mmol/L range in 0.1 steps. For each source
    /// value, importing must produce a mg/dL whose mmol/L display equals
    /// the source value. This is the broad guarantee the prior PR couldn't
    /// make, and the test bjorn asked for ("structured test of more values").
    @Test("0.1 mmol/L sweep across therapy range round-trips cleanly") func sweep_0_1_mmolL_range() {
        // 1.0 to 30.0 mmol/L in 0.1 steps. Covers ISF (typically 1–22) and
        // target lows/highs (typically 4–11) with comfortable headroom.
        var source = d("1.0")
        let step = d("0.1")
        let end = d("30.0")
        while source <= end {
            let mgdL = source.asMgdLForImport
            #expect(
                mgdL.asMmolL == source,
                "Sweep miss at \(source) mmol/L: \(mgdL) mg/dL displays as \(mgdL.asMmolL)"
            )
            source += step
        }
    }
}

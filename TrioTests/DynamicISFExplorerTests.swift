import Foundation
import Testing

@testable import Trio

@Suite("Dynamic ISF Explorer Tests") struct DynamicISFExplorerTests {
    typealias Inputs = DynamicISFExplorer.Inputs
    typealias Curve = DynamicISFExplorer.Curve
    typealias ActiveOverride = DynamicISFExplorer.ActiveOverride

    let inputs = Inputs(
        sigmoid: false,
        adjustmentFactor: 0.8,
        adjustmentFactorSigmoid: 0.5,
        autosensMin: 0.8,
        autosensMax: 1.2,
        insulinPeakTime: 65,
        sensitivity: 46,
        target: 100,
        tddLast24Hours: 45,
        tddTenDayAverage: 50,
        weightPercentage: 0.35
    )

    @Test("Weighted TDD blends the last 24 hours with the 10-day average") func weightedTDD() {
        #expect(inputs.weightedTDD == 48.25)
    }

    @Test("Logarithmic curve matches the Dynamic ISF formula") func logarithmicFormula() throws {
        let curve = try #require(Curve(inputs: inputs, override: nil))
        let point = try #require(curve.points.first { $0.glucose == 100 })

        // ratio = ISF × AF × weighted TDD × ln(glucose / (120 - peak) + 1) / 1800
        let expected = 46 * 0.8 * 48.25 * Foundation.log(100.0 / 55 + 1) / 1800
        #expect(abs(Double(truncating: point.ratio as NSNumber) - expected) < 0.0001)
        #expect(point.sensitivity == 45)
    }

    @Test("Curve is clamped to the Autosens limits") func clampedToAutosensLimits() throws {
        let curve = try #require(Curve(inputs: inputs, override: nil))

        #expect(curve.points.first?.glucose == 40)
        #expect(curve.points.first?.ratio == 0.8)
        #expect(curve.points.first?.sensitivity == 57.5)
        #expect(curve.points.last?.glucose == 400)
        #expect(curve.points.last?.ratio == 1.2)
        #expect(curve.points.last?.sensitivity == 38.3)
        #expect(curve.profileSensitivity == 46)
        #expect(curve.sensitivityLimits.upperBound == 57.5)
    }

    @Test("Sigmoid curve crosses the profile ISF at the target") func sigmoidCrossesProfileAtTarget() throws {
        var inputs = inputs
        inputs.sigmoid = true

        let curve = try #require(Curve(inputs: inputs, override: nil))
        let atTarget = try #require(curve.points.first { $0.glucose == 100 })

        #expect(abs(atTarget.ratio - 1) < 0.001)
        #expect(atTarget.sensitivity == 46)
    }

    @Test("No curve when Dynamic ISF would be off") func offWithoutRoomOrTDD() {
        var noRoom = inputs
        noRoom.autosensMin = 1
        noRoom.autosensMax = 1
        #expect(Curve(inputs: noRoom, override: nil) == nil)

        var noTDD = inputs
        noTDD.tddLast24Hours = 0
        noTDD.tddTenDayAverage = 0
        #expect(Curve(inputs: noTDD, override: nil) == nil)
    }

    @Test("Autosens limits work either way round, as in the algorithm") func swappedAutosensLimits() throws {
        var swapped = inputs
        swapped.autosensMin = 1
        swapped.autosensMax = 0.9

        let curve = try #require(Curve(inputs: swapped, override: nil))

        #expect(curve.sensitivityLimits == 46 / swapped.autosensMin ... 46 / swapped.autosensMax)
        #expect(curve.points.allSatisfy { (0.9 ... 1).contains($0.ratio) })
    }

    @Test("Stepping glucose in mmol/L lands back on the saved mg/dL value") func glucoseStepRoundTrip() {
        let range: ClosedRange<Decimal> = 9 ... 540
        let up = Inputs.glucose(46.asMmolL + 0.1, in: .mmolL, saved: 46, range: range)
        #expect(up == 49)
        #expect(Inputs.glucose(up.asMmolL - 0.1, in: .mmolL, saved: 46, range: range) == 46)

        #expect(Inputs.glucose(101, in: .mgdL, saved: 100, range: range) == 101)
        #expect(Inputs.glucose(100, in: .mgdL, saved: 100, range: range) == 100)
    }

    @Test("Stepped glucose stays within range after converting from mmol/L") func glucoseStepStaysInRange() {
        // 4.4 mmol/L converts to 79 mg/dL, below the loop's 80 mg/dL target floor
        #expect(Inputs.glucose(80.asMmolL, in: .mmolL, saved: 99, range: 80 ... 180) == 80)
    }

    @Test("An override scales the profile ISF and limits") func overrideScalesSensitivity() throws {
        let override = ActiveOverride(percentage: 80, adjustsSensitivity: true, target: nil)
        let curve = try #require(Curve(inputs: inputs, override: override))

        #expect(curve.profileSensitivity == 57.5)
        #expect(curve.points.first?.sensitivity == 71.9)
        #expect(curve.sensitivityLimits.upperBound == 71.875)
    }

    @Test("An override target moves where the sigmoid crosses the profile ISF") func overrideTargetMovesSigmoid() throws {
        var inputs = inputs
        inputs.sigmoid = true
        let override = ActiveOverride(percentage: 100, adjustsSensitivity: false, target: 120)

        let curve = try #require(Curve(inputs: inputs, override: override))
        let atOverrideTarget = try #require(curve.points.first { $0.glucose == 120 })

        #expect(abs(atOverrideTarget.ratio - 1) < 0.001)
    }

    @Test("Active override is read from the last loop's variables") func activeOverrideFromVariables() {
        #expect(ActiveOverride(variables(useOverride: false, isf: true, overrideTarget: 120)) == nil)
        #expect(ActiveOverride(variables(useOverride: true, isf: false, overrideTarget: 0)) == nil)
        #expect(ActiveOverride(variables(useOverride: true, isf: false, overrideTarget: 6)) == nil)
        #expect(
            ActiveOverride(variables(useOverride: true, isf: true, overrideTarget: 0)) ==
                ActiveOverride(percentage: 80, adjustsSensitivity: true, target: nil)
        )
        #expect(
            ActiveOverride(variables(useOverride: true, isf: false, overrideTarget: 120)) ==
                ActiveOverride(percentage: 80, adjustsSensitivity: false, target: 120)
        )
        #expect(
            ActiveOverride(variables(useOverride: true, isf: false, isfAndCr: true, overrideTarget: 0)) ==
                ActiveOverride(percentage: 80, adjustsSensitivity: true, target: nil)
        )
        // at 100% the ISF adjustment changes nothing
        #expect(ActiveOverride(variables(useOverride: true, isf: true, overridePercentage: 100, overrideTarget: 0)) == nil)
        #expect(
            ActiveOverride(variables(useOverride: true, isf: true, overridePercentage: 100, overrideTarget: 120)) ==
                ActiveOverride(percentage: 100, adjustsSensitivity: false, target: 120)
        )
    }

    @Test("Nearest point snaps to the closest glucose step") func nearestPoint() throws {
        let curve = try #require(Curve(inputs: inputs, override: nil))

        #expect(curve.point(nearest: 102)?.glucose == 100)
        #expect(curve.point(nearest: 999)?.glucose == 400)
    }

    private func variables(
        useOverride: Bool,
        isf: Bool,
        isfAndCr: Bool = false,
        overridePercentage: Decimal = 80,
        overrideTarget: Decimal
    ) -> TrioCustomOrefVariables {
        TrioCustomOrefVariables(
            average_total_data: 50,
            weightedAverage: 48,
            currentTDD: 45,
            past2hoursAverage: 45,
            date: Date(),
            overridePercentage: overridePercentage,
            useOverride: useOverride,
            duration: 0,
            unlimited: true,
            overrideTarget: overrideTarget,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: isfAndCr,
            isf: isf,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )
    }
}

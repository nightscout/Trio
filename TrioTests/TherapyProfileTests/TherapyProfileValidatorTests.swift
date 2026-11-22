import Foundation
import Testing
@testable import Trio

@Suite("Therapy Profile Validator Tests") struct TherapyProfileValidatorTests {
    private let limits = TherapyProfileTestRecorder().basalLimits

    @Test("A well-formed profile passes") func validProfile() {
        #expect(TherapyProfileValidator.validate(TherapyProfileFixtures.profile("Ok"), basalLimits: limits) == nil)
    }

    @Test("Malformed schedules are rejected", arguments: [
        [(Int, Double)](),
        [(1800, 1)],
        [(0, 1), (0, 1.1)],
        [(0, 1), (3600, 1.1), (1800, 1.2)],
        [(0, 1), (900, 1.1)],
        [(0, 1), (86400, 1.1)],
        (0 ..< 49).map { ($0 % 48 * 1800, 1) }
    ]) func malformedSchedules(_ basal: [(Int, Double)]) {
        #expect(TherapyProfileValidator.validate(TherapyProfileFixtures.profile("Bad", basal: basal), basalLimits: limits) != nil)
    }

    @Test(
        "Basal 0, above max basal and unsupported rates are rejected",
        arguments: [0, 3.05, 0.07]
    ) func basalRules(_ rate: Double) {
        #expect(
            TherapyProfileValidator
                .validate(TherapyProfileFixtures.profile("Bad", basal: [(0, rate)]), basalLimits: limits) != nil
        )
    }

    @Test("Max basal itself is accepted") func maxBasalAccepted() {
        #expect(
            TherapyProfileValidator
                .validate(TherapyProfileFixtures.profile("Max", basal: [(0, 3)]), basalLimits: limits) == nil
        )
    }

    @Test("Out-of-range and off-step values are rejected") func valueRanges() {
        let invalid = [
            TherapyProfileFixtures.profile("a", carbratio: [(0, 0.9)]),
            TherapyProfileFixtures.profile("b", carbratio: [(0, 50.1)]),
            TherapyProfileFixtures.profile("c", carbratio: [(0, 10.05)]),
            TherapyProfileFixtures.profile("d", sens: [(0, 8)]),
            TherapyProfileFixtures.profile("e", sens: [(0, 541)]),
            TherapyProfileFixtures.profile("f", sens: [(0, 50.5)]),
            TherapyProfileFixtures.profile("g", target: [(0, 71, 71)]),
            TherapyProfileFixtures.profile("h", target: [(0, 181, 181)])
        ]
        for profile in invalid {
            #expect(TherapyProfileValidator.validate(profile, basalLimits: limits) != nil, "\(profile.name)")
        }
        let edges = TherapyProfileFixtures.profile(
            "edges",
            carbratio: [(0, 1), (1800, 50)],
            sens: [(0, 9), (1800, 540)],
            target: [(0, 72, 72), (1800, 180, 180)]
        )
        #expect(TherapyProfileValidator.validate(edges, basalLimits: limits) == nil)
    }

    @Test("A change is checked in the changed schedules only") func validateChanges() {
        let stored = TherapyProfileFixtures.profile("Stored", basal: [(0, 3.5)])
        #expect(TherapyProfileValidator.validate(stored, basalLimits: limits) != nil)
        let newRatio = TherapyProfileFixtures.profile("Stored", basal: [(0, 3.5)], carbratio: [(0, 12)])
        #expect(TherapyProfileValidator.validateChanges(newRatio, from: stored, basalLimits: limits) == nil)
        let badRatio = TherapyProfileFixtures.profile("Stored", basal: [(0, 3.5)], carbratio: [(0, 0.5)])
        #expect(TherapyProfileValidator.validateChanges(badRatio, from: stored, basalLimits: limits) != nil)
        let fixedBasal = TherapyProfileFixtures.profile("Stored", basal: [(0, 2)])
        #expect(TherapyProfileValidator.validateChanges(fixedBasal, from: stored, basalLimits: limits) == nil)
    }

    @Test("Every value the carb ratio, ISF and target editors offer passes, and one step outside fails", arguments: [
        GlucoseUnits.mgdL,
        .mmolL
    ]) func editorValues(units: GlucoseUnits) {
        let pickers = PickerSettingsProvider.shared
        let ratios = CarbRatioEditor.StateModel().rateValues
        let sensitivities = pickers.generatePickerValues(
            from: TherapyProfileLimits.sensitivity.glucosePickerSetting(value: 100),
            units: units
        )
        let targets = pickers.generatePickerValues(
            from: TherapyProfileLimits.target.glucosePickerSetting(value: 110),
            units: units
        )
        for ratio in ratios {
            #expect(TherapyProfileValidator.validateCarbRatios(Self.profile(carbRatio: ratio)) == nil, "\(ratio)")
        }
        for sensitivity in sensitivities {
            #expect(
                TherapyProfileValidator.validateSensitivities(Self.profile(sensitivity: sensitivity)) == nil,
                "\(sensitivity)"
            )
        }
        for target in targets {
            #expect(TherapyProfileValidator.validateTargets(Self.profile(target: target)) == nil, "\(target)")
        }
        let ratio = TherapyProfileLimits.carbRatio
        #expect(ratios.first == ratio.min && ratios.last == ratio.max)
        #expect(TherapyProfileValidator.validateCarbRatios(Self.profile(carbRatio: ratio.min - ratio.step)) != nil)
        #expect(TherapyProfileValidator.validateCarbRatios(Self.profile(carbRatio: ratio.max + ratio.step)) != nil)
        let sensitivity = TherapyProfileLimits.sensitivity
        #expect(
            TherapyProfileValidator
                .validateSensitivities(Self.profile(sensitivity: sensitivity.min - sensitivity.step)) != nil
        )
        #expect(
            TherapyProfileValidator
                .validateSensitivities(Self.profile(sensitivity: sensitivity.max + sensitivity.step)) != nil
        )
        let target = TherapyProfileLimits.target
        #expect(TherapyProfileValidator.validateTargets(Self.profile(target: target.min - target.step)) != nil)
        #expect(TherapyProfileValidator.validateTargets(Self.profile(target: target.max + target.step)) != nil)
    }

    @Test("The basal editor offers the rates the validator accepts") func basalEditorRates() {
        let omnipod = BasalProfileEditor.Provider.editorRates((0 ... 600).map { Double($0) / 20 })
        let rates = BasalProfileEditor.StateModel.rateValues(supportedRates: omnipod, maxBasal: 3)
        let limits = TherapyBasalLimits(supportedRates: omnipod, maxBasal: 3)
        #expect(rates.first == TherapyProfileFixtures.decimal(0.05))
        #expect(rates.last == 3)
        for rate in rates {
            let profile = TherapyProfileFixtures.profile("Rate", basal: [(0, Double(truncating: rate as NSNumber))])
            #expect(TherapyProfileValidator.validateBasal(profile, basalLimits: limits) == nil, "\(rate)")
        }
        let noPump = BasalProfileEditor.StateModel.rateValues(supportedRates: nil, maxBasal: 2)
        #expect(noPump.first == TherapyProfileFixtures.decimal(0.05))
        #expect(noPump.last == 2)
        #expect(BasalProfileEditor.StateModel.rateValues(supportedRates: omnipod, maxBasal: 0.01) == omnipod)
    }

    private static func profile(carbRatio: Decimal = 10, sensitivity: Decimal = 50, target: Decimal = 100) -> TrioTherapyProfile {
        TrioTherapyProfile(
            name: "Picker",
            basal: [TherapyScheduleEntry(seconds: 0, value: 1)],
            carbRatio: [TherapyScheduleEntry(seconds: 0, value: carbRatio)],
            sensitivity: [TherapyScheduleEntry(seconds: 0, value: sensitivity)],
            target: [TherapyTargetEntry(seconds: 0, low: target, high: target)]
        )
    }

    @Test("Name rules") func names() {
        #expect(TherapyProfileValidator.validateName("Sport", existingNames: ["Default"]) == nil)
        #expect(TherapyProfileValidator.validateName(String(repeating: "x", count: 32), existingNames: []) == nil)
        for invalid in ["", " Sport", String(repeating: "x", count: 33), "a.b", "$set", "default", "DEFAULT"] {
            #expect(TherapyProfileValidator.validateName(invalid, existingNames: []) != nil, "\(invalid)")
        }
        #expect(TherapyProfileValidator.validateName("sport", existingNames: ["Sport"]) != nil)
        #expect(TherapyProfileValidator.validateName("Default", existingNames: [], isDefaultProfile: true) == nil)
        #expect(TherapyProfileValidator.validateName("Sick day 🤒", existingNames: []) == nil)
        #expect(TherapyProfileValidator.validateName("Two  words", existingNames: []) == nil)
        #expect(TherapyProfileValidator.validateName(String(repeating: "👨‍👩‍👧‍👦", count: 32), existingNames: []) == nil)
        #expect(TherapyProfileValidator.validateName(String(repeating: "👨‍👩‍👧‍👦", count: 33), existingNames: []) != nil)
        #expect(TherapyProfileValidator.validateName("Cafe\u{301}", existingNames: ["Caf\u{E9}"]) != nil)
    }
}

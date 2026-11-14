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

import Foundation
import Testing
@testable import Trio

@Suite("Therapy Profile Remote Values Tests") struct TherapyProfileRemoteValuesTests {
    @Test("Compact values decode in mg/dL and mmol/L") func compactDecode() throws {
        let json =
            #"{"units":"mmol/L","basal":[[0,0.85],[21600,1.0]],"carbratio":[[0,10]],"sens":[[0,2.8]],"target":[[0,5.6,6.1]]}"#
        let profile = try JSONDecoder().decode(CompactTherapyProfile.self, from: Data(json.utf8)).therapyProfile(named: "M")
        #expect(profile.sensitivity == [TherapyScheduleEntry(seconds: 0, value: 50)])
        #expect(profile.target == [TherapyTargetEntry(seconds: 0, low: 101, high: 101)])
        #expect(profile.basal.map(\.value) == [TherapyProfileFixtures.decimal(0.85), 1])

        let mgdL = CompactTherapyProfile(
            units: "mg/dL",
            basal: [[0, 0.85]],
            carbratio: [[0, 10]],
            sens: [[0, 50]],
            target: [[0, 100, 110]]
        )
        #expect(try mgdL.therapyProfile(named: "G").target == [TherapyTargetEntry(seconds: 0, low: 100, high: 100)])
    }

    @Test("Unchanged mmol/L values keep the stored mg/dL values") func compactKeepsOriginal() throws {
        let original = TherapyProfileFixtures.profile("W", sens: [(0, 55)], target: [(0, 104, 105)])
        let compact = CompactTherapyProfile(
            units: "mmol/L",
            basal: [[0, 0.85]],
            carbratio: [[0, 10]],
            sens: [[0, 3.1], [43200, 3.1]],
            target: [[0, 5.8, 6.1]]
        )
        let profile = try compact.therapyProfile(named: "W", original: original)
        #expect(profile.sensitivity.map(\.seconds) == [0, 43200])
        #expect(profile.sensitivity.map(\.value) == [55, 56])
        #expect(profile.target == [TherapyTargetEntry(seconds: 0, low: 104, high: 104)])
    }

    @Test("Malformed compact values are rejected") func compactMalformed() {
        let malformed = [
            CompactTherapyProfile(
                units: "furlongs",
                basal: [[0, 1]],
                carbratio: [[0, 10]],
                sens: [[0, 50]],
                target: [[0, 100, 110]]
            ),
            CompactTherapyProfile(units: "mg/dL", basal: [[0]], carbratio: [[0, 10]], sens: [[0, 50]], target: [[0, 100, 110]]),
            CompactTherapyProfile(
                units: "mg/dL",
                basal: [[0.5, 1]],
                carbratio: [[0, 10]],
                sens: [[0, 50]],
                target: [[0, 100, 110]]
            ),
            CompactTherapyProfile(units: "mg/dL", basal: [[0, 1]], carbratio: [[0, 10]], sens: [[0, 50]], target: [[0, 100]])
        ]
        for compact in malformed {
            #expect(throws: TherapyProfileError.self) { try compact.therapyProfile(named: "X") }
        }
    }

    @Test("profileEditLimits has the contract keys") func editLimits() throws {
        let limits = NightscoutProfileEditLimits(
            units: .mgdL,
            basalLimits: TherapyBasalLimits(
                supportedRates: [0.05, 0.1, 0.15, 0.2, 5].map(TherapyProfileFixtures.decimal),
                maxBasal: TherapyProfileFixtures.decimal(0.15)
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(limits)) as? [String: Any])
        #expect(object["units"] as? String == "mg/dL")
        #expect(object["basalRates"] as? [Double] == [0.05, 0.1, 0.15])
        #expect(object["basalMinimum"] as? Double == 0.05)
        #expect(object["maxBasal"] as? Double == 0.15)
        #expect(object["maxSegments"] as? Int == 48)
        #expect(object["segmentSeconds"] as? Int == 1800)
        #expect(object["carbRatio"] as? [String: Double] == ["min": 1, "max": 50, "step": 0.1])
        #expect(object["sensitivity"] as? [String: Double] == ["min": 9, "max": 540, "step": 1])
        #expect(object["target"] as? [String: Double] == ["min": 72, "max": 180, "step": 1])

        let mmolL = NightscoutProfileEditLimits(units: .mmolL, basalLimits: TherapyBasalLimits(supportedRates: [1], maxBasal: 1))
        #expect(mmolL.units == "mmol/L")
        #expect(mmolL.target == .init(min: 4, max: 10, step: 0.1))
        #expect(mmolL.sensitivity == .init(min: 0.5, max: TherapyProfileFixtures.decimal(29.9), step: 0.1))
    }

    @Test("A mmol/L profile at the published limits is accepted") func mmolLAtLimits() throws {
        let basalLimits = TherapyBasalLimits(supportedRates: [1], maxBasal: 1)
        let limits = NightscoutProfileEditLimits(units: .mmolL, basalLimits: basalLimits)
        func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
        for (sens, target) in [(limits.sensitivity.max, limits.target.max), (limits.sensitivity.min, limits.target.min)] {
            let compact = CompactTherapyProfile(
                units: "mmol/L",
                basal: [[0, 1]],
                carbratio: [[0, 10]],
                sens: [[0, double(sens)]],
                target: [[0, double(target), double(target)]]
            )
            #expect(TherapyProfileValidator.validate(try compact.therapyProfile(named: "M"), basalLimits: basalLimits) == nil)
        }
    }

    @Test("Profile commands are listed as supported") func remoteCommands() {
        let commands = TrioRemoteControl.CommandType.supported.map(\.rawValue)
        #expect(commands.contains("switch_profile"))
        #expect(commands.contains("save_profile"))
        #expect(commands.contains("delete_profile"))
    }
}

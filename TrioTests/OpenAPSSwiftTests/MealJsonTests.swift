import Foundation
import Testing
@testable import Trio

@Suite("Testing meal using JSON inputs") struct MealJsonTests {
    @Test("Test against simulator inputs") func simulatorInputs() throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "meal-input-sim", ofType: "json")!
        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        // this file stores an object with JSON encoded strings (so double encoded)
        let jsonInputs = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let pumpHistory = try JSONBridge.pumpHistory(from: jsonInputs["pumpHistory"] as! String)
        let profile = try JSONBridge.profile(from: jsonInputs["profile"] as! String)
        let basalProfile = try JSONBridge.basalProfile(from: jsonInputs["basalProfile"] as! String)
        let clock = try JSONBridge.clock(from: jsonInputs["clock"] as! String)

        let decoder = JSONCoding.decoder
        var jsonData = (jsonInputs["carbs"] as! String).data(using: .utf8)!
        let carbHistory: [CarbsEntry] = try decoder.decode([CarbsEntry].self, from: jsonData)

        jsonData = (jsonInputs["glucose"] as! String).data(using: .utf8)!
        let glucoseHistory: [BloodGlucose] = try decoder.decode([BloodGlucose].self, from: jsonData)

        jsonData = (jsonInputs["meal"] as! String).data(using: .utf8)!
        let mealResultFromJs = try decoder.decode(ComputedCarbs.self, from: jsonData)

        let mealResult = MealGeneratorError.generate(
            pumpHistory: pumpHistory,
            profile: profile,
            basalProfile: basalProfile,
            clock: clock,
            carbHistory: carbHistory,
            glucoseHistory: glucoseHistory
        )

        // we need something like this
        // #expect(mealResult == mealResultFromJs)
    }
}

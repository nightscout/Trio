import Foundation
import Testing

@testable import Trio

@Suite("Remote Meal Mutation Payload Tests") struct RemoteMealMutationPayloadTests {
    private func decode(_ json: String) throws -> CommandPayload {
        try JSONDecoder().decode(CommandPayload.self, from: Data(json.utf8))
    }

    @Test("delete_meal payload decodes with command_id and meal_id") func testDecodeDeleteMeal() throws {
        let mealID = UUID()
        let payload = try decode("""
        {"user":"caregiver","command_type":"delete_meal","timestamp":1700000000,
         "command_id":"6C0F1D2E-9B3A-4C5D-8E7F-000000000001","meal_id":"\(mealID.uuidString)"}
        """)

        #expect(payload.commandType == .deleteMeal)
        #expect(payload.commandId == "6C0F1D2E-9B3A-4C5D-8E7F-000000000001")
        #expect(payload.mealHandle == mealID)
        #expect(payload.carbs == nil)
    }

    @Test("edit_meal payload decodes replacement values") func testDecodeEditMeal() throws {
        let payload = try decode("""
        {"user":"caregiver","command_type":"edit_meal","timestamp":1700000000,
         "command_id":"x","meal_id":"\(UUID().uuidString)",
         "carbs":45,"fat":0,"protein":15,"scheduled_time":1700000100}
        """)

        #expect(payload.commandType == .editMeal)
        #expect(payload.carbs == 45)
        #expect(payload.fat == 0)
        #expect(payload.protein == 15)
        #expect(payload.scheduledTime == 1_700_000_100)
        #expect(payload.humanReadableDescription().contains("Edit Meal"))
    }

    @Test("Unknown command types decode to .unknown") func testDecodeUnknownCommandType() throws {
        let payload = try decode("""
        {"user":"caregiver","command_type":"start_dance","timestamp":1700000000}
        """)

        #expect(payload.commandType == .unknown)
        #expect(payload.humanReadableDescription().contains("Unknown"))
    }

    @Test("Malformed meal_id yields no handle") func testMalformedMealID() throws {
        let payload = try decode("""
        {"user":"caregiver","command_type":"delete_meal","timestamp":1700000000,"meal_id":"abc"}
        """)

        #expect(payload.mealHandle == nil)
        #expect(payload.mealId == "abc")
    }

    @Test("Supported command list excludes unknown") func testSupportedCommands() {
        let supported = TrioRemoteControl.CommandType.supported.map(\.rawValue)
        #expect(supported.contains("delete_meal"))
        #expect(supported.contains("edit_meal"))
        #expect(supported.contains("meal"))
        #expect(!supported.contains("unknown"))
    }

    @Test("Ack payload encodes command_id, meal_id and result when present") func testAckEncoding() throws {
        let payload = RemoteNotificationResponseManager.NotificationPayload(
            aps: .init(alert: .init(title: "t", body: "b")),
            commandStatus: "success",
            commandType: "delete_meal",
            timestamp: 1,
            commandId: "cmd",
            mealId: "meal",
            result: "deleted"
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]

        #expect(json?["command_id"] as? String == "cmd")
        #expect(json?["meal_id"] as? String == "meal")
        #expect(json?["result"] as? String == "deleted")
        #expect(json?["command_status"] as? String == "success")
    }

    @Test("Ack payload omits the new keys when absent") func testAckEncodingOmitsNil() throws {
        let payload = RemoteNotificationResponseManager.NotificationPayload(
            aps: .init(alert: .init(title: "t", body: "b")),
            commandStatus: "failed",
            commandType: "bolus",
            timestamp: 1,
            commandId: nil,
            mealId: nil,
            result: nil
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]

        #expect(json?["command_id"] == nil)
        #expect(json?["meal_id"] == nil)
        #expect(json?["result"] == nil)
    }

    @Test("Result raw values match the wire protocol") func testResultRawValues() {
        #expect(RemoteCommandAck.Result.deleted.rawValue == "deleted")
        #expect(RemoteCommandAck.Result.updated.rawValue == "updated")
        #expect(RemoteCommandAck.Result.notFound.rawValue == "not_found")
        #expect(RemoteCommandAck.Result.rejected.rawValue == "rejected")
    }

    @Test("Meal age window") func testMealAgeWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(TrioRemoteControl.validateMealAge(now.addingTimeInterval(-23 * 3600), now: now) == nil)
        #expect(TrioRemoteControl.validateMealAge(now.addingTimeInterval(-25 * 3600), now: now) != nil)
        #expect(TrioRemoteControl.validateMealAge(now.addingTimeInterval(11 * 3600), now: now) == nil)
        #expect(TrioRemoteControl.validateMealAge(now.addingTimeInterval(13 * 3600), now: now) != nil)
    }

    @Test("Edit input validation") func testEditInputValidation() {
        func validate(_ carbs: Int, _ fat: Int, _ protein: Int) -> String? {
            TrioRemoteControl.validateEditMealInput(
                carbs: carbs, fat: fat, protein: protein, maxCarbs: 100, maxFat: 50, maxProtein: 50
            )
        }
        #expect(validate(40, 0, 0) == nil)
        #expect(validate(0, 20, 10) == nil)
        #expect(validate(0, 0, 0) != nil)
        #expect(validate(-1, 0, 0) != nil)
        #expect(validate(101, 0, 0) != nil)
        #expect(validate(0, 51, 0) != nil)
        #expect(validate(0, 0, 51) != nil)
    }
}

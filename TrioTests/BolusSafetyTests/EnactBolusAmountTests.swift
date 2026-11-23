import Foundation
import Swinject
import Testing
@testable import Trio

/// A bolus of zero or less must be refused with an answer. `enactBolus` used to return without
/// calling back, so a watch that sent 0 U waited on "Processing…" forever.
@Suite("Enact bolus amount validation", .serialized) struct EnactBolusAmountTests {
    private static func makeAPSManager() async throws -> APSManager {
        let coreDataStack = try await CoreDataStack.createForTests()
        let resolver = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: coreDataStack.newTaskContext())
        ]).resolver
        return try #require(resolver.resolve(APSManager.self))
    }

    @Test("Bolus of zero or less is refused with an answer", arguments: [
        0.0,
        -0.05,
        -3.0,
        Double.nan
    ]) func testInvalidAmountAnswersFailure(amount: Double) async throws {
        let apsManager = try await Self.makeAPSManager()
        var answers: [(success: Bool, message: String)] = []

        await apsManager.enactBolus(amount: amount, isSMB: false) { success, message in
            answers.append((success, message))
        }

        #expect(answers.count == 1)
        #expect(answers.first?.success == false)
        #expect(answers.first?.message == BaseAPSManager.invalidBolusAmountMessage)
    }
}

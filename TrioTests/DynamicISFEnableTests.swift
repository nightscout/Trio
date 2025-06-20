import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("Dynamic ISF Enable Logic Tests", .serialized) struct DynamicISFEnableTests {
    var coreDataStack: CoreDataStack!
    var context: NSManagedObjectContext!

    init() async throws {
        // In-memory Core Data for tests
        coreDataStack = try await CoreDataStack.createForTests()
        context = coreDataStack.newTaskContext()
    }

    func testEnableLogic(percentSamples: Double) async throws -> Bool {
        let numberOfSamples = Int(288 * 7 * percentSamples)
        let now = Date() // internal function uses Date()

        try await context.perform {
            for index in 0 ..< numberOfSamples {
                let timeDelta = Double(index * 5 * 60)
                let tdd = TDDStored(context: context)
                tdd.date = now - timeDelta
                tdd.total = 30
                tdd.bolus = 15
                tdd.tempBasal = 15
                tdd.scheduledBasal = 0
            }

            try context.save()
        }

        return try await BaseTDDStorage.hasSufficientTDD(context: context)
    }

    @Test("Confirm samples from last 7 days enables Dynamic ISF") func testPercentSamplesEnablingLogic() async throws {
        let enabled = try await testEnableLogic(percentSamples: 0.8)
        #expect(enabled)
    }

    @Test("Confirm insufficient samples from last 7 days disables Dynamic ISF") func testPercentSamplesDisablesLogic() async throws {
        let enabled = try await testEnableLogic(percentSamples: 0.7)
        #expect(!enabled)
    }
}

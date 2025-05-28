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

    @Test("Confirm 80% of samples from last 7 days enables Dynamic ISF") func test80PercentSamplesEnablingLogic() async throws {
        let numberOfSamples = Int(288 * 7 * 0.8) // 80% of 7 days of samples
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

        let enabled = try await BaseTDDStorage.hasSufficientTDD(context: context)
        #expect(enabled)
    }
}

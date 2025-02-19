import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("CarbsStorage Tests") struct CarbsStorageTests: Injectable {
    @Injected() var storage: CarbsStorage!
    let resolver: Resolver
    let coreDataStack = CoreDataStack.createForTests()
    let testContext: NSManagedObjectContext

    init() {
        // Create test context
        testContext = coreDataStack.newTaskContext()

        // Create assembler with test assembly
        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext) // Add our test assembly last to override CarbsStorage
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        // Verify storage exists
        #expect(storage != nil, "CarbsStorage should be injected")

        // Verify it's the correct type
        #expect(
            storage is BaseCarbsStorage, "Storage should be of type BaseCarbsStorage"
        )

        // Verify we can access the update publisher
        #expect(storage.updatePublisher != nil, "Update publisher should be available")
    }
}

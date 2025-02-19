import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("TempTargetStorage Tests") struct TempTargetsStorageTests: Injectable {
    @Injected() var storage: TempTargetsStorage!
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
            TestAssembly(testContext: testContext) // Add our test assembly last to override TempTargetStorage
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        // Verify storage exists
        #expect(storage != nil, "TempTargetsStorage should be injected")

        // Verify it's the correct type
        #expect(
            storage is BaseTempTargetsStorage, "Storage should be of type BaseTempTargetsStorage"
        )
    }
}

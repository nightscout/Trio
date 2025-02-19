import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("GlucoseStorage Tests") struct GlucoseStorageTests: Injectable {
    @Injected() var storage: GlucoseStorage!
    let resolver: Resolver
    let coreDataStack = CoreDataStack.createForTests()
    let testContext: NSManagedObjectContext

    init() {
        // Create test context
        // As we are only using this single test context to initialize our in-memory DeterminationStorage we need to perform the Unit Tests serialized
        testContext = coreDataStack.newTaskContext()

        // Create assembler with test assembly
        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext) // Add our test assembly last to override Storage
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        // Verify storage exists
        #expect(storage != nil, "GlucoseStorage should be injected")

        // Verify it's the correct type
        #expect(storage is BaseGlucoseStorage, "Storage should be of type BaseGlucoseStorage")
    }
}

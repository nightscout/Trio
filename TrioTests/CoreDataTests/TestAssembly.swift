import CoreData
import Foundation
import Swinject
@testable import Trio

class TestAssembly: Assembly {
    private let testContext: NSManagedObjectContext

    init(testContext: NSManagedObjectContext) {
        self.testContext = testContext
    }

    func assemble(container: Container) {
        // Override PumpHistoryStorage registration for tests
        container.register(PumpHistoryStorage.self) { r in
            BasePumpHistoryStorage(resolver: r, context: self.testContext)
        }.inObjectScope(.container)

        // Override DeterminationStorage registration for tests
        container.register(DeterminationStorage.self) { r in
            BaseDeterminationStorage(resolver: r, context: self.testContext)
        }.inObjectScope(.container)
    }
}

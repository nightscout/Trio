//
// Trio
// TestAssembly.swift
// Created by Marvin Polscheit on 2025-02-13.
// Last edited by Marvin Polscheit on 2025-02-19.
// Most contributions by Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

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

        // Override CarbsStorage registration for tests
        container.register(CarbsStorage.self) { r in
            BaseCarbsStorage(resolver: r, context: self.testContext)
        }.inObjectScope(.container)

        // Override GlucoseStorage registration for tests
        container.register(GlucoseStorage.self) { r in
            BaseGlucoseStorage(resolver: r, context: self.testContext)
        }.inObjectScope(.container)

        // Override TempTargetStorage registration for tests
        container.register(TempTargetsStorage.self) { r in
            BaseTempTargetsStorage(resolver: r, context: self.testContext)
        }.inObjectScope(.container)

        // Override OverrideStorage registration for tests
        container.register(OverrideStorage.self) { r in
            BaseOverrideStorage(resolver: r, context: self.testContext)
        }.inObjectScope(.container)
    }
}

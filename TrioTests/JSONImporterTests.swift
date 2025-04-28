//
//  JSONImporterTests.swift
//  Trio
//
//  Created by Cengiz Deniz on 21.04.25.
//
import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

class BundleReference {}

@Suite("JSON Importer Tests") struct JSONImporterTests: Injectable {
    var coreDataStack: CoreDataStack!
    var context: NSManagedObjectContext!
    var importer: JSONImporter!

    init() async throws {
        // In-memory Core Data for tests
        coreDataStack = try await CoreDataStack.createForTests()
        context = coreDataStack.newTaskContext()
        importer = JSONImporter(context: context, coreDataStack: coreDataStack)
    }

    @Test("Import glucose history with value checks") func testImportGlucoseHistoryDetails() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "glucose", ofType: "json")!
        let url = URL(filePath: path)

        try await importer.importGlucoseHistory(url: url)
        // run the import againt to check our deduplication logic
        try await importer.importGlucoseHistory(url: url)

        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored] ?? []

        #expect(allReadings.count == 274)
        #expect(allReadings.first?.glucose == 115)
        #expect(allReadings.first?.date == Date(timeIntervalSince1970: 1_745_868_771.726578))
        #expect(allReadings.last?.glucose == 127)
        #expect(allReadings.last?.date == Date(timeIntervalSince1970: 1_745_782_670.3270996))

        let manualCount = allReadings.filter({ $0.isManual }).count
        #expect(manualCount == 1)
    }
}

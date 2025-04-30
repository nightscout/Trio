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

@Suite("JSON Importer Tests", .serialized) struct JSONImporterTests: Injectable {
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

        let now = Date("2025-04-28T19:32:52.000Z")!
        try await importer.importGlucoseHistory(url: url, now: now)
        // run the import againt to check our deduplication logic
        try await importer.importGlucoseHistory(url: url, now: now)

        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored] ?? []

        #expect(allReadings.count == 274)
        #expect(allReadings.first?.glucose == 115)
        #expect(allReadings.first?.date == Date("2025-04-28T19:32:51.727Z"))
        #expect(allReadings.last?.glucose == 127)
        #expect(allReadings.last?.date == Date("2025-04-27T19:37:50.327Z"))

        let manualCount = allReadings.filter({ $0.isManual }).count
        #expect(manualCount == 1)
    }

    @Test("Skip importing old glucose values") func testSkipImportOldGlucoseValues() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "glucose", ofType: "json")!
        let url = URL(filePath: path)

        // more than 24 hours in the future from the most recent entry
        let now = Date("2025-04-29T19:32:52.000Z")!
        try await importer.importGlucoseHistory(url: url, now: now)

        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored] ?? []

        #expect(allReadings.isEmpty)
    }
}

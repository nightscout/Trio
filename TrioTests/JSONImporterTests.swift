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
    @Injected() var determinationStorage: DeterminationStorage!

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

    @Test("Import determination data with value checks") func testImportDeterminationDetails() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let enactedPath = testBundle.path(forResource: "enacted", ofType: "json")!
        let enactedUrl = URL(filePath: enactedPath)
        let suggestedPath = testBundle.path(forResource: "suggested", ofType: "json")!
        let suggestedUrl = URL(filePath: suggestedPath)

        let now = Date("2025-04-28T20:50:00.000Z")!
        try await importer.importOrefDetermination(enactedUrl: enactedUrl, suggestedUrl: suggestedUrl, now: now)
        // run the import againt to check our deduplication logic
        try await importer.importOrefDetermination(enactedUrl: enactedUrl, suggestedUrl: suggestedUrl, now: now)

        let determinations = try await coreDataStack.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "deliverAt",
            ascending: false
        ) as? [OrefDetermination] ?? []

        #expect(determinations.count == 1) // single determination, as enacted.deliverAt and suggested.deliverAt match

        let determination = determinations.first!

        #expect(determination.deliverAt == Date("2025-04-28T19:41:43.564Z"))
        #expect(determination.timestamp == Date("2025-04-28T19:41:48.453Z"))
        #expect(determination.enacted == true)
        #expect(determination.reason?.starts(with: "Autosens ratio: 0.99") == true)
        #expect(determination.insulinReq == Decimal(string: "0.29").map(NSDecimalNumber.init))
        #expect(determination.eventualBG! == NSDecimalNumber(160))
        #expect(determination.sensitivityRatio == Decimal(string: "0.9863849810728643").map(NSDecimalNumber.init))
        #expect(determination.rate == Decimal(string: "0").map(NSDecimalNumber.init))
        #expect(determination.duration == NSDecimalNumber(60))
        #expect(determination.iob == Decimal(string: "1.249").map(NSDecimalNumber.init))
        #expect(determination.cob == 34)
        #expect(determination.temp == "absolute")
        #expect(determination.glucose == NSDecimalNumber(85))
        #expect(determination.reservoir == Decimal(string: "3735928559").map(NSDecimalNumber.init))
        #expect(determination.insulinSensitivity == Decimal(string: "4.6").map(NSDecimalNumber.init))
        #expect(determination.currentTarget == Decimal(string: "94").map(NSDecimalNumber.init))
        #expect(determination.insulinForManualBolus == Decimal(string: "0.8").map(NSDecimalNumber.init))
        #expect(determination.manualBolusErrorString == Decimal(string: "0").map(NSDecimalNumber.init))
        #expect(determination.minDelta == NSDecimalNumber(5))
        #expect(determination.expectedDelta == Decimal(string: "-5.9").map(NSDecimalNumber.init))
        #expect(determination.threshold == Decimal(string: "3.7").map(NSDecimalNumber.init))
        #expect(determination.carbRatio == nil) // not present in JSON

        // TODO: fix forecast testing
//        let forecastHierarchy = try await determinationStorage.fetchForecastHierarchy(for: determination.objectID, in: context)
//
//        for entry in forecastHierarchy {
//            let (_, forecast, values) = await determinationStorage.fetchForecastObjects(for: entry, in: context)
//
//            // Basic checks
//            #expect(forecast != nil)
//            #expect(!values.isEmpty)
//
//            if let forecast = forecast {
//                let sortedValues = values.sorted { $0.index < $1.index }
//                let prefix = sortedValues.prefix(5).compactMap(\.value)
//                let type = forecast.type?.lowercased()
//
//                switch type {
//                case "zt":
//                    #expect(prefix == [85, 78, 71, 64, 58])
//                case "iob":
//                    #expect(prefix == [85, 89, 92, 95, 97])
//                case "uam":
//                    #expect(prefix == [85, 89, 93, 96, 99])
//                case "cob":
//                    #expect(prefix == [85, 90, 94, 99, 103])
//                default:
//                    break // Skip unknown forecast types silently
//                }
//            }
//        }
    }
}

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

    @Test("Import pump history with value checks") func testImportPumpHistoryDetails() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "pumphistory-24h-zoned", ofType: "json")!
        let url = URL(filePath: path)

        let now = Date("2025-04-29T01:33:58.000Z")!
        try await importer.importPumpHistory(url: url, now: now)
        // test out deduplication logic
        try await importer.importPumpHistory(url: url, now: now)

        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "timestamp",
            ascending: false
        ) as? [PumpEventStored] ?? []

        let objectIds = allReadings.map(\.objectID)
        let parsedHistory = OpenAPS.loadAndMapPumpEvents(objectIds, from: context)

        var bolusTotal = 0.0
        var bolusCount = 0
        var smbCount = 0
        var rateTotal = 0.0
        var tempBasalCount = 0
        var durationTotal = 0
        var suspendCount = 0
        var resumeCount = 0
        for event in parsedHistory {
            switch event {
            case let .bolus(bolus):
                bolusTotal += bolus.amount
                bolusCount += 1
                if bolus.isSMB {
                    smbCount += 1
                }
            case let .tempBasal(tempBasal):
                rateTotal += tempBasal.rate
                tempBasalCount += 1
            case let .tempBasalDuration(tempBasalDuration):
                durationTotal += tempBasalDuration.duration
            case .suspend:
                suspendCount += 1
            case .resume:
                resumeCount += 1
            default:
                fatalError("unhandled pump event")
            }
        }

        #expect(parsedHistory.count == 77)
        #expect(bolusCount == 23)
        #expect(smbCount == 21)
        #expect(bolusTotal.isApproximatelyEqual(to: 8.1, epsilon: 0.01))
        #expect(tempBasalCount == 26)
        #expect(rateTotal.isApproximatelyEqual(to: 20.08, epsilon: 0.001))
        #expect(durationTotal == 900)
        #expect(suspendCount == 1)
        #expect(resumeCount == 1)
    }
}

extension Double {
    func isApproximatelyEqual(to other: Double, epsilon: Double?) -> Bool {
        // If no epsilon provided, require exact match
        guard let epsilon = epsilon else {
            return self == other
        }

        // Handle exact equality
        if self == other {
            return true
        }

        // Handle infinity and NaN
        if isInfinite || other.isInfinite || isNaN || other.isNaN {
            return self == other
        }

        // For values, use simple absolute difference
        return abs(self - other) <= epsilon
    }
}

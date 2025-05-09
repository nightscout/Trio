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

        // see the scripts/pump-history-stats.py file for where these come from
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

    @Test("Skipping old pump history entries") func testSkipOldPumpHistoryEntries() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "pumphistory-24h-zoned", ofType: "json")!
        let url = URL(filePath: path)

        let now = Date("2025-04-30T01:33:58.000Z")!
        try await importer.importPumpHistory(url: url, now: now)

        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "timestamp",
            ascending: false
        ) as? [PumpEventStored] ?? []

        #expect(allReadings.isEmpty)
    }

    @Test("Import pump history with external insulin") func testImportPumpHistoryWithExternalInsulin() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "pumphistory-with-external", ofType: "json")!
        let url = URL(filePath: path)

        let now = Date("2025-05-04T04:37:44.654Z")!
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

        #expect(parsedHistory.count == 1)

        let bolus: BolusDTO? = {
            switch parsedHistory.first! {
            case let .bolus(bolus):
                return bolus
            default:
                return nil
            }
        }()

        #expect(bolus != nil)
        #expect(bolus!.isExternal)
        #expect(bolus!.amount.isApproximatelyEqual(to: 0.88, epsilon: 0.01))
    }

    @Test("Import carb history with value checks") func testImportCarbHistoryDetails() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "carbhistory", ofType: "json")!
        let url = URL(filePath: path)

        let now = Date("2025-04-28T19:32:52.000Z")!
        try await importer.importCarbHistory(url: url, now: now)
        // run the import againt to check our deduplication logic
        try await importer.importCarbHistory(url: url, now: now)

        let allCarbEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored] ?? []

        #expect(allCarbEntries.count == 8)
        #expect(allCarbEntries.first?.carbs == 10)
        #expect(allCarbEntries.first?.note == "Snack 🍪")
        #expect(allCarbEntries.first?.date == Date("2025-04-28T18:36:06.968Z"))
        #expect(allCarbEntries.last?.carbs == 25)
        #expect(allCarbEntries.last?.date == Date("2025-04-28T05:03:43.332Z"))
    }

    @Test("Skip importing old carb entries") func testSkipImportOldCarbEntries() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "carbhistory", ofType: "json")!
        let url = URL(filePath: path)

        // more than 24 hours in the future from the most recent entry
        let now = Date("2025-04-29T19:32:52.000Z")!
        try await importer.importCarbHistory(url: url, now: now)

        let allCarbEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored] ?? []

        #expect(allCarbEntries.isEmpty)
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

        let forecasts = try await coreDataStack.fetchEntitiesAsync(
            ofType: Forecast.self,
            onContext: context,
            predicate: NSPredicate(format: "orefDetermination = %@", determination.objectID),
            key: "type",
            ascending: true,
            relationshipKeyPathsForPrefetching: ["forecastValues"]
        )

        var forecastHierarchy: [(forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID])] = []

        await context.perform {
            if let forecasts = forecasts as? [Forecast] {
                for forecast in forecasts {
                    // Use the helper property that already sorts by index
                    let sortedValues = forecast.forecastValuesArray
                    forecastHierarchy.append((
                        forecastID: forecast.objectID,
                        forecastValueIDs: sortedValues.map(\.objectID)
                    ))
                }
            }

            for entry in forecastHierarchy {
                var forecastValueTuple: (Forecast?, [ForecastValue]) = (nil, [])

                var forecast: Forecast?
                var forecastValues: [ForecastValue] = []

                do {
                    // Fetch the forecast object
                    forecast = try context.existingObject(with: entry.forecastID) as? Forecast

                    // Fetch the first 3h of forecast values
                    for forecastValueID in entry.forecastValueIDs.prefix(36) {
                        if let forecastValue = try context.existingObject(with: forecastValueID) as? ForecastValue {
                            forecastValues.append(forecastValue)
                        }
                    }
                } catch {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch forecast Values with error: \(error.localizedDescription)"
                    )
                }
                forecastValueTuple = (forecast, forecastValues)

                // Basic checks
                #expect(forecastValueTuple.0 != nil)
                #expect(forecastValueTuple.1.isNotEmpty == true)

                if let forecast = forecastValueTuple.0 {
                    let sortedValues = forecastValueTuple.1.sorted { $0.index < $1.index }
                    let prefix = sortedValues.prefix(5).compactMap(\.value)
                    let type = forecast.type?.lowercased()

                    switch type {
                    case "zt":
                        #expect(prefix == [85, 78, 71, 64, 58])
                    case "iob":
                        #expect(prefix == [85, 89, 92, 95, 97])
                    case "uam":
                        #expect(prefix == [85, 89, 93, 96, 99])
                    case "cob":
                        #expect(prefix == [85, 90, 94, 99, 103])
                    default:
                        break // Skip unknown forecast types silently
                    }
                }
            }
        }
    }

    @Test("Skip importing old determinations") func testSkipImportOldDeterminationData() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let enactedPath = testBundle.path(forResource: "enacted", ofType: "json")!
        let enactedUrl = URL(filePath: enactedPath)
        let suggestedPath = testBundle.path(forResource: "suggested", ofType: "json")!
        let suggestedUrl = URL(filePath: suggestedPath)

        // more than 24 hours in the future from the most recent entry
        let now = Date("2025-04-29T22:00:00.000Z")!

        try await importer.importOrefDetermination(enactedUrl: enactedUrl, suggestedUrl: suggestedUrl, now: now)

        let determinations = try await coreDataStack.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "deliverAt",
            ascending: false
        ) as? [OrefDetermination] ?? []

        #expect(determinations.isEmpty)
    }

    @Test("Import determination data with suggested newer than enacted") func testImportDeterminationDetailsWithNewerSuggested(
    ) async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let enactedPath = testBundle.path(forResource: "enacted", ofType: "json")!
        let enactedUrl = URL(filePath: enactedPath)
        let suggestedPath = testBundle.path(forResource: "newerSuggested", ofType: "json")!
        let suggestedUrl = URL(filePath: suggestedPath)

        let now = Date("2025-04-28T20:50:00.000Z")!
        try await importer.importOrefDetermination(enactedUrl: enactedUrl, suggestedUrl: suggestedUrl, now: now)

        let determinations = try await coreDataStack.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "deliverAt",
            ascending: false
        ) as? [OrefDetermination] ?? []

        #expect(determinations.count == 2) // two determinations, suggested is more recent than enacted

        let suggested = determinations.first(where: { !$0.enacted && $0.deliverAt == $0.timestamp })!
        let enacted = determinations.first(where: { $0.enacted })!

        #expect(suggested.deliverAt == Date("2025-04-28T19:51:48.453Z"))
        #expect(enacted.timestamp == Date("2025-04-28T19:41:48.453Z"))
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

import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite(.serialized) struct DeterminationStorageTests: Injectable {
    @Injected() var storage: DeterminationStorage!
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
        #expect(storage != nil, "DeterminationStorage should be injected")

        // Verify it's the correct type
        #expect(storage is BaseDeterminationStorage, "Storage should be of type BaseDeterminationStorage")
    }

    @Test("Test fetchLastDeterminationObjectID with different predicates") func testFetchLastDeterminationWithPredicates() async throws {
        // Given
        let date = Date()
        let id = UUID()

        // Create a mock determination
        await testContext.perform {
            let determination = OrefDetermination(context: testContext)
            determination.id = id
            determination.deliverAt = date
            determination.timestamp = date
            determination.enacted = true
            determination.isUploadedToNS = true
            try? testContext.save()
        }

        // Tests with predicates that we use the most for this function
        // 1. Test within 30 minutes
        let results = await storage.fetchLastDeterminationObjectID(predicate: NSPredicate.predicateFor30MinAgoForDetermination)
        #expect(results.count == 1, "Should find 1 determination within 30 minutes")
        // Get NSManagedObjectID from exactDateResults
        try await testContext.perform {
            do {
                guard let results = results.first,
                      let object = try testContext.existingObject(with: results) as? OrefDetermination
                else {
                    throw TestError("Failed to fetch determination")
                }
                #expect(object.timestamp == date, "Determination within 30 minutes should have the same timestamp as date")
                #expect(object.deliverAt == date, "Determination within 30 minutes should have the same deliverAt as date")
                #expect(object.enacted == true, "Determination within 30 minutes should be enacted")
                #expect(object.isUploadedToNS == true, "Determination within 30 minutes should be uploaded to NS")
                #expect(object.id == id, "Determination within 30 minutes should have the same id")
            } catch {
                throw TestError("Failed to fetch determination")
            }
        }

        // 2. Test enacted determinations
        let enactedPredicate = NSPredicate.enactedDetermination
        let enactedResults = await storage.fetchLastDeterminationObjectID(predicate: enactedPredicate)
        #expect(enactedResults.count == 1, "Should find 1 enacted determination")
        // Get NSManagedObjectID from enactedResults
        try await testContext.perform {
            do {
                guard let results = enactedResults.first,
                      let object = try testContext.existingObject(with: results) as? OrefDetermination
                else {
                    throw TestError("Failed to fetch determination")
                }
                #expect(object.enacted == true, "Enacted determination should be enacted")
                #expect(object.isUploadedToNS == true, "Enacted determination should be uploaded to NS")
                #expect(object.id == id, "Enacted determination should have the same id")
                #expect(object.timestamp == date, "Enacted determination should have the same timestamp")
                #expect(object.deliverAt == date, "Enacted determination should have the same deliverAt")

                // Delete the determination
                testContext.delete(object)
                try testContext.save()
            } catch {
                throw TestError("Failed to fetch determination")
            }
        }
    }

//    @Test("Test complete forecast hierarchy prefetching") func testForecastHierarchyPrefetching() async throws {
//        // Given
//        let date = Date()
//        let backgroundContext = CoreDataStack.shared.newTaskContext()
//        let forecastTypes = ["iob", "cob", "zt", "uam"]
//
//        // Create test determination with complete forecast hierarchy
//        let determination = OrefDetermination(context: backgroundContext)
//        determination.id = UUID()
//        determination.deliverAt = date
//
//        // Create all forecast types with values
//        for type in forecastTypes {
//            let forecast = Forecast(context: backgroundContext)
//            forecast.id = UUID()
//            forecast.date = date
//            forecast.type = type
//            forecast.orefDetermination = determination
//
//            // Add test values
//            for i in 0 ..< 5 {
//                let value = ForecastValue(context: backgroundContext)
//                value.index = Int32(i)
//                value.value = Int32(100 + (i * 10))
//                value.forecast = forecast
//            }
//        }
//
//        try await backgroundContext.save()
//
//        // When - Fetch complete hierarchy
//        let request = NSFetchRequest<OrefDetermination>(entityName: "OrefDetermination")
//        request.predicate = NSPredicate(format: "SELF = %@", determination.objectID)
//        request.relationshipKeyPathsForPrefetching = ["forecasts", "forecasts.forecastValues"]
//
//        let fetchedDetermination = try await backgroundContext.perform {
//            try request.execute().first
//        }
//
//        // Then
//        #expect(fetchedDetermination != nil)
//        #expect(fetchedDetermination?.forecasts?.count == 4)
//
//        let forecasts = fetchedDetermination?.forecasts?.allObjects as? [Forecast] ?? []
//        for forecast in forecasts {
//            #expect(forecastTypes.contains(forecast.type ?? ""))
//            #expect(forecast.forecastValues?.count == 5)
//
//            let values = forecast.forecastValuesArray
//            #expect(values.count == 5)
//            for (index, value) in values.enumerated() {
//                #expect(value.value == Int32(100 + (index * 10)))
//            }
//        }
//
//        // Cleanup
//        await backgroundContext.perform {
//            backgroundContext.delete(determination)
//            try? backgroundContext.save()
//        }
//    }

//    @Test("Test forecast handling with multiple forecast types") func testMultipleForecastTypes() async throws {
//        // Given
//        let date = Date()
//        let backgroundContext = CoreDataStack.shared.newTaskContext()
//        var determinationId: NSManagedObjectID?
//        let forecastTypes = ["iob", "cob", "zt", "uam"]
//        var forecastIds: [NSManagedObjectID] = []
//
//        // Create test data with multiple forecast types
//        await backgroundContext.perform {
//            let determination = OrefDetermination(context: backgroundContext)
//            determination.id = UUID()
//            determination.deliverAt = date
//
//            // Create forecasts for each type
//            for type in forecastTypes {
//                let forecast = Forecast(context: backgroundContext)
//                forecast.id = UUID()
//                forecast.date = date
//                forecast.type = type
//                forecast.orefDetermination = determination
//
//                // Add some values
//                for i in 0 ..< 3 {
//                    let value = ForecastValue(context: backgroundContext)
//                    value.index = Int32(i)
//                    value.value = Int32(100 + i * 10)
//                    value.forecast = forecast
//                }
//
//                forecastIds.append(forecast.objectID)
//            }
//
//            try? backgroundContext.save()
//            determinationId = determination.objectID
//        }
//
//        guard let determinationId = determinationId else {
//            throw TestError("Failed to create test data")
//        }
//
//        // When - Fetch all forecasts
//        let allForecastIds = await storage.getForecastIDs(for: determinationId, in: backgroundContext)
//
//        // Then
//        #expect(allForecastIds.count == forecastTypes.count, "Should have found all forecast types")
//
//        // Test each forecast type
//        for forecastId in forecastIds {
//            // When - Fetch values for this forecast
//            let valueIds = await storage.getForecastValueIDs(for: forecastId, in: backgroundContext)
//
//            // Then
//            #expect(valueIds.count == 3, "Each forecast should have 3 values")
//
//            // When - Fetch complete objects
//            let (_, forecast, values) = await storage.fetchForecastObjects(
//                for: (UUID(), forecastId, valueIds),
//                in: backgroundContext
//            )
//
//            // Then
//            #expect(forecast != nil, "Should have found the forecast")
//            #expect(forecastTypes.contains(forecast?.type ?? ""), "Should have valid forecast type")
//            #expect(values.count == 3, "Should have all forecast values")
//        }
//
//        // Test Nightscout format with multiple forecasts
//        let nsFormat = await storage.getOrefDeterminationNotYetUploadedToNightscout([determinationId])
//        #expect(nsFormat?.predictions?.iob?.count == 3, "Should have IOB predictions")
//        #expect(nsFormat?.predictions?.cob?.count == 3, "Should have COB predictions")
//        #expect(nsFormat?.predictions?.zt?.count == 3, "Should have ZT predictions")
//        #expect(nsFormat?.predictions?.uam?.count == 3, "Should have UAM predictions")
//
//        // Cleanup
//        await CoreDataStack.shared.deleteObject(identifiedBy: determinationId)
//    }
}

import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("Determination Storage Tests", .serialized) struct DeterminationStorageTests: Injectable {
    @Injected() var storage: DeterminationStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        // Create test context
        // As we are only using this single test context to initialize our in-memory DeterminationStorage we need to perform the Unit Tests serialized
        coreDataStack = try await CoreDataStack.createForTests()
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
        let results = try await storage
            .fetchLastDeterminationObjectID(predicate: NSPredicate.predicateFor30MinAgoForDetermination)
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
        let enactedResults = try await storage.fetchLastDeterminationObjectID(predicate: enactedPredicate)
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

    @Test("Test complete forecast hierarchy prefetching") func testForecastHierarchyPrefetching() async throws {
        // Given
        let date = Date()
        let forecastTypes = ["iob", "cob", "zt", "uam"]
        let expectedValuesPerForecast = 5

        // STEP 1: Create test data
        let id = try await createTestData(
            date: date,
            forecastTypes: forecastTypes,
            expectedValuesPerForecast: expectedValuesPerForecast
        )

        // STEP 2: Test hierarchy fetching
        let hierarchy = try await storage.fetchForecastHierarchy(
            for: id,
            in: testContext
        )

        // Test hierarchy structure
        #expect(hierarchy.count == forecastTypes.count, "Should have correct number of forecasts")

        // STEP 3: Test individual forecasts
        for data in hierarchy {
            let (_, forecast, values) = await storage.fetchForecastObjects(
                for: data,
                in: testContext
            )

            // Test basic structure
            #expect(forecast != nil, "Forecast should exist")
            #expect(values.count == expectedValuesPerForecast, "Should have correct number of values")

            // Test forecast type and values
            if let forecast = forecast {
                #expect(forecastTypes.contains(forecast.type ?? ""), "Should have valid forecast type")

                // Test value patterns
                let sortedValues = values.sorted { $0.index < $1.index }
                switch forecast.type {
                case "iob":
                    #expect(sortedValues.first?.value == 100, "IOB should start at 100")
                    #expect(sortedValues.last?.value == 140, "IOB should end at 140")
                case "cob":
                    #expect(sortedValues.first?.value == 50, "COB should start at 50")
                    #expect(sortedValues.last?.value == 70, "COB should end at 70")
                case "zt":
                    #expect(sortedValues.first?.value == 80, "ZT should start at 80")
                    #expect(sortedValues.last?.value == 112, "ZT should end at 112")
                case "uam":
                    #expect(sortedValues.first?.value == 120, "UAM should start at 120")
                    #expect(sortedValues.last?.value == 60, "UAM should end at 60")
                default:
                    break
                }
            }
        }

        // STEP 4: Test relationship integrity
        try await testContext.perform {
            do {
                let determination = try testContext.existingObject(with: id) as? OrefDetermination
                let forecasts = Array(determination?.forecasts ?? [])

                #expect(forecasts.count == forecastTypes.count, "Determination should have all forecasts")
                #expect(
                    forecasts.allSatisfy { Array($0.forecastValues ?? []).count == expectedValuesPerForecast },
                    "Each forecast should have correct number of values"
                )
            } catch {
                throw TestError("Failed to verify relationships: \(error)")
            }
        }
    }

    private func createTestData(
        date: Date,
        forecastTypes: [String],
        expectedValuesPerForecast: Int
    ) async throws -> NSManagedObjectID {
        try await testContext.perform {
            let determination = OrefDetermination(context: testContext)
            determination.id = UUID()
            determination.deliverAt = date
            determination.timestamp = date
            determination.enacted = true

            // Create all forecast types with values
            for type in forecastTypes {
                let forecast = Forecast(context: testContext)
                forecast.id = UUID()
                forecast.date = date
                forecast.type = type
                forecast.orefDetermination = determination

                // Add test values with different patterns per type
                for i in 0 ..< expectedValuesPerForecast {
                    let value = ForecastValue(context: testContext)
                    value.index = Int32(i)

                    // Different value patterns for each type
                    switch type {
                    case "iob": value.value = Int32(100 + i * 10) // 100, 110, 120...
                    case "cob": value.value = Int32(50 + i * 5) // 50, 55, 60...
                    case "zt": value.value = Int32(80 + i * 8) // 80, 88, 96...
                    case "uam": value.value = Int32(120 - i * 15) // 120, 105, 90...
                    default: value.value = 0
                    }

                    value.forecast = forecast
                }
            }

            do {
                try testContext.save()

                return determination.objectID
            } catch {
                throw TestError("Failed to create test data: \(error)")
            }
        }
    }
}

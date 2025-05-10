import Combine
import CoreData
import Foundation
import SwiftDate
import Swinject

protocol CarbsObserver {
    func carbsDidUpdate(_ carbs: [CarbsEntry])
}

protocol CarbsStorage {
    var updatePublisher: AnyPublisher<Void, Never> { get }
    func storeCarbs(_ carbs: [CarbsEntry], areFetchedFromRemote: Bool) async throws
    func deleteCarbsEntryStored(_ treatmentObjectID: NSManagedObjectID) async
    func syncDate() -> Date
    func getCarbsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getFPUsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getCarbsNotYetUploadedToHealth() async throws -> [CarbsEntry]
    func getCarbsNotYetUploadedToTidepool() async throws -> [CarbsEntry]
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    private let updateSubject = PassthroughSubject<Void, Never>()

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    private let context: NSManagedObjectContext

    init(resolver: Resolver, context: NSManagedObjectContext? = nil) {
        self.context = context ?? CoreDataStack.shared.newTaskContext()
        injectServices(resolver)
    }

    func storeCarbs(_ entries: [CarbsEntry], areFetchedFromRemote: Bool) async throws {
        var entriesToStore = entries

        if areFetchedFromRemote {
            entriesToStore = try await filterRemoteEntries(entries: entriesToStore)
        }

        // Check for FPU-only entries (fat/protein without carbs)
        let fpuOnlyEntries = entriesToStore.filter { entry in
            entry.carbs == 0 && (entry.fat ?? 0 > 0 || entry.protein ?? 0 > 0)
        }

        // Create additional Carb (non-FPU) entries with fat/protein amounts and carbs == 0
        for entry in fpuOnlyEntries {
            let additionalEntry = CarbsEntry(
                id: entry.id,
                createdAt: entry.createdAt,
                actualDate: entry.actualDate,
                carbs: Decimal(0),
                fat: entry.fat,
                protein: entry.protein,
                note: entry.note,
                enteredBy: entry.enteredBy,
                isFPU: false, // it should be a Carb entry
                fpuID: entry.fpuID
            )
            entriesToStore.append(additionalEntry)
        }

        await saveCarbsToCoreData(entries: entriesToStore, areFetchedFromRemote: areFetchedFromRemote)
        await saveCarbEquivalents(entries: entriesToStore, areFetchedFromRemote: areFetchedFromRemote)
    }

    private func filterRemoteEntries(entries: [CarbsEntry]) async throws -> [CarbsEntry] {
        // Fetch only the date property from Core Data
        guard let existing24hCarbEntries = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false,
            batchSize: 50,
            propertiesToFetch: ["date", "objectID"]
        ) as? [[String: Any]] else {
            return entries
        }

        // Extract dates into a set for efficient lookup
        // Since we are not dealing with NSManagedObjects directly it is safe to pass properties between threads
        let existingTimestamps = Set(existing24hCarbEntries.compactMap { $0["date"] as? Date })

        // Remove all entries that have a matching date in existingTimestamps
        var filteredEntries = entries
        filteredEntries.removeAll { entry in
            let entryDate = entry.actualDate ?? entry.createdAt
            return existingTimestamps.contains(entryDate)
        }

        return filteredEntries
    }

    /**
     Calculates the duration for processing FPUs (fat and protein units) based on the FPUs and the time cap.

     - The function uses predefined rules to determine the duration based on the number of FPUs.
     - Ensures that the duration does not exceed the time cap.

     - Parameters:
       - fpus: The number of FPUs calculated from fat and protein.
       - timeCap: The maximum allowed duration.

     - Returns: The computed duration in hours.
     */
    private func calculateComputedDuration(fpus: Decimal, timeCap: Int) -> Int {
        switch fpus {
        case ..<2:
            return 3
        case 2 ..< 3:
            return 4
        case 3 ..< 4:
            return 5
        default:
            return timeCap
        }
    }

    /**
     Processes fat and protein entries to generate future carb equivalents, ensuring each equivalent is at least 1.0 grams.

     - The function calculates the equivalent carb dosage size and adjusts the interval to ensure each equivalent is at least 1.0 grams.
     - Creates future carb entries based on the adjusted carb equivalent size and interval.

     - Parameters:
       - entries: An array of `CarbsEntry` objects representing the carbohydrate entries to be processed.
       - fat: The amount of fat in the last entry.
       - protein: The amount of protein in the last entry.
       - createdAt: The creation date of the last entry.

     - Returns: A tuple containing the array of future carb entries and the total carb equivalents.
     */
    private func processFPU(
        entries: [CarbsEntry],
        fat: Decimal,
        protein: Decimal,
        createdAt: Date,
        actualDate: Date?
    ) -> ([CarbsEntry], Decimal) {
        let interval = settings.settings.minuteInterval
        let timeCap = settings.settings.timeCap
        let adjustment = settings.settings.individualAdjustmentFactor
        let delay = settings.settings.delay

        let kcal = protein * 4 + fat * 9
        let carbEquivalents = (kcal / 10) * adjustment
        let fpus = carbEquivalents / 10
        var computedDuration = calculateComputedDuration(fpus: fpus, timeCap: timeCap)

        var carbEquivalentSize: Decimal = carbEquivalents / Decimal(computedDuration)
        carbEquivalentSize /= Decimal(60 / interval)

        if carbEquivalentSize < 1.0 {
            carbEquivalentSize = 1.0
            computedDuration = Int(carbEquivalents / carbEquivalentSize)
        }

        let roundedEquivalent: Double = round(Double(carbEquivalentSize * 10)) / 10
        carbEquivalentSize = Decimal(roundedEquivalent)
        var numberOfEquivalents = carbEquivalents / carbEquivalentSize

        var useDate = actualDate ?? createdAt
        let fpuID = entries.first?.fpuID ?? UUID().uuidString
        var futureCarbArray = [CarbsEntry]()
        var firstIndex = true

        while carbEquivalents > 0, numberOfEquivalents > 0 {
            useDate = firstIndex ? useDate.addingTimeInterval(delay.minutes.timeInterval) : useDate
                .addingTimeInterval(interval.minutes.timeInterval)
            firstIndex = false

            let eachCarbEntry = CarbsEntry(
                id: UUID().uuidString,
                createdAt: createdAt,
                actualDate: useDate,
                carbs: carbEquivalentSize,
                fat: 0,
                protein: 0,
                note: nil,
                enteredBy: CarbsEntry.local,
                isFPU: true,
                fpuID: fpuID
            )
            futureCarbArray.append(eachCarbEntry)
            numberOfEquivalents -= 1
        }

        return (futureCarbArray, carbEquivalents)
    }

    private func saveCarbEquivalents(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        guard let lastEntry = entries.last else { return }

        if let fat = lastEntry.fat, let protein = lastEntry.protein, fat > 0 || protein > 0 {
            let (futureCarbEquivalents, carbEquivalentCount) = processFPU(
                entries: entries,
                fat: fat,
                protein: protein,
                createdAt: lastEntry.createdAt,
                actualDate: lastEntry.actualDate
            )

            if carbEquivalentCount > 0 {
                await saveFPUToCoreDataAsBatchInsert(entries: futureCarbEquivalents, areFetchedFromRemote: areFetchedFromRemote)
            }
        }
    }

    private func saveCarbsToCoreData(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        guard let entry = entries.last else { return }

        await context.perform {
            let newItem = CarbEntryStored(context: self.context)
            newItem.date = entry.actualDate ?? entry.createdAt
            newItem.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            newItem.fat = Double(truncating: NSDecimalNumber(decimal: entry.fat ?? 0))
            newItem.protein = Double(truncating: NSDecimalNumber(decimal: entry.protein ?? 0))
            newItem.note = entry.note
            newItem.id = UUID()
            newItem.isFPU = false
            newItem.isUploadedToNS = areFetchedFromRemote ? true : false
            newItem.isUploadedToHealth = false
            newItem.isUploadedToTidepool = false

            if entry.fat != nil, entry.protein != nil, let fpuId = entry.fpuID {
                newItem.fpuID = UUID(uuidString: fpuId)
            }

            do {
                guard self.context.hasChanges else { return }
                try self.context.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    private func saveFPUToCoreDataAsBatchInsert(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        let commonFPUID = UUID(
            uuidString: entries.first?.fpuID ?? UUID()
                .uuidString
        ) // all fpus should only get ONE id per batch insert to be able to delete them referencing the fpuID
        var entrySlice = ArraySlice(entries) // convert to ArraySlice
        let batchInsert = NSBatchInsertRequest(entity: CarbEntryStored.entity()) { (managedObject: NSManagedObject) -> Bool in
            guard let carbEntry = managedObject as? CarbEntryStored, let entry = entrySlice.popFirst(),
                  let entryId = entry.id
            else {
                return true // return true to stop
            }
            carbEntry.date = entry.actualDate
            carbEntry.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            carbEntry.id = UUID.init(uuidString: entryId)
            carbEntry.fpuID = commonFPUID
            carbEntry.isFPU = true
            carbEntry.isUploadedToNS = areFetchedFromRemote ? true : false
            // do NOT set Health and Tidepool flags to ensure they will NOT be uploaded
            return false // return false to continue
        }
        await context.perform {
            do {
                try self.context.execute(batchInsert)
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.succeeded) saved fpus to core data")

                // Notify subscriber in Home State Model to update the FPU Array
                self.updateSubject.send(())
            } catch {
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.failed) error while saving fpus to core data")
            }
        }
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func deleteCarbsEntryStored(_ treatmentObjectID: NSManagedObjectID) async {
        // Use injected context if available, otherwise create new task context
        let taskContext = context != CoreDataStack.shared.newTaskContext()
            ? context
            : CoreDataStack.shared.newTaskContext()

        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "deleteCarbs"

        var carbEntryFromCoreData: CarbEntryStored?

        await taskContext.perform {
            do {
                carbEntryFromCoreData = try taskContext.existingObject(with: treatmentObjectID) as? CarbEntryStored
                guard let carbEntry = carbEntryFromCoreData else {
                    debugPrint("Carb entry for batch delete not found. \(DebuggingIdentifiers.failed)")
                    return
                }

                // entry has fpuID
                // case 1: carb equivalent entry
                // case 2: "parent" entry, but containing fat and/or protein, and possibly carbs
                // => use fpuID ID to delete all corresponding entries via batch delete
                if let fpuID = carbEntry.fpuID {
                    // fetch request for all carb entries with the same id
                    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CarbEntryStored.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "fpuID == %@", fpuID as CVarArg)

                    // NSBatchDeleteRequest
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                    deleteRequest.resultType = .resultTypeCount

                    // execute the batch delete request
                    let result = try taskContext.execute(deleteRequest) as? NSBatchDeleteResult
                    debugPrint("\(DebuggingIdentifiers.succeeded) Deleted \(result?.result ?? 0) items with FpuID \(fpuID)")

                    // Notifiy subscribers of the batch delete
                    self.updateSubject.send(())
                }
                // entry has no fpuID
                // => it's a carb-only entry. use its ID to for deletion
                else {
                    taskContext.delete(carbEntry)

                    guard taskContext.hasChanges else { return }
                    try taskContext.save()

                    debugPrint(
                        "CarbsStorage: \(#function) \(DebuggingIdentifiers.succeeded) deleted carb entry from core data"
                    )
                }

            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error deleting carb entry: \(error)")
            }
        }
    }

    func getCarbsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.carbsNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let carbEntries = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return carbEntries.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.local,
                    bolus: nil,
                    insulin: nil,
                    notes: result.note,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    foodType: result.note,
                    targetTop: nil,
                    targetBottom: nil,
                    id: result.id?.uuidString
                )
            }
        }
    }

    func getFPUsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.fpusNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fpuEntries = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fpuEntries.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.local,
                    bolus: nil,
                    insulin: nil,
                    notes: result.note,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    foodType: result.note,
                    targetTop: nil,
                    targetBottom: nil,
                    id: result.fpuID?.uuidString
                )
            }
        }
    }

    func getCarbsNotYetUploadedToHealth() async throws -> [CarbsEntry] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.carbsNotYetUploadedToHealth,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let carbEntries = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return carbEntries.map { result in
                CarbsEntry(
                    id: result.id?.uuidString,
                    createdAt: result.date ?? Date(),
                    actualDate: result.date,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    note: result.note,
                    enteredBy: CarbsEntry.local,
                    isFPU: result.isFPU,
                    fpuID: result.fpuID?.uuidString
                )
            }
        }
    }

    func getCarbsNotYetUploadedToTidepool() async throws -> [CarbsEntry] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.carbsNotYetUploadedToTidepool,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let carbEntries = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return carbEntries.map { result in
                CarbsEntry(
                    id: result.id?.uuidString,
                    createdAt: result.date ?? Date(),
                    actualDate: result.date,
                    carbs: Decimal(result.carbs),
                    fat: nil,
                    protein: nil,
                    note: result.note,
                    enteredBy: CarbsEntry.local,
                    isFPU: nil,
                    fpuID: nil
                )
            }
        }
    }
}

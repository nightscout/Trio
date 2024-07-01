import CoreData
import Foundation
import SwiftDate
import Swinject

protocol CarbsObserver {
    func carbsDidUpdate(_ carbs: [CarbsEntry])
}

protocol CarbsStorage {
    func storeCarbs(_ carbs: [CarbsEntry])
    func syncDate() -> Date
    func recent() -> [CarbsEntry]
    func getCarbsNotYetUploadedToNightscout() async -> [NightscoutTreatment]
    func getFPUsNotYetUploadedToNightscout() async -> [NightscoutTreatment]
    func deleteCarbs(at uniqueID: String, fpuID: String, complex: Bool)
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    let coredataContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ entries: [CarbsEntry]) {
        processQueue.sync {
            self.storeCarbEquivalents(entries: entries)
            self.saveCarbsToCoreData(entries: entries)
        }
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
    private func processFPU(entries _: [CarbsEntry], fat: Decimal, protein: Decimal, createdAt: Date) -> ([CarbsEntry], Decimal) {
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

        var useDate = createdAt
        let fpuID = UUID().uuidString
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
                enteredBy: CarbsEntry.manual, isFPU: true,
                fpuID: fpuID
            )
            futureCarbArray.append(eachCarbEntry)
            numberOfEquivalents -= 1
        }

        return (futureCarbArray, carbEquivalents)
    }

    private func storeCarbEquivalents(entries: [CarbsEntry]) {
        guard let lastEntry = entries.last else { return }

        if let fat = lastEntry.fat, let protein = lastEntry.protein, fat > 0 || protein > 0 {
            let (futureCarbEquivalents, carbEquivalentCount) = processFPU(
                entries: entries,
                fat: fat,
                protein: protein,
                createdAt: lastEntry.createdAt
            )

            if carbEquivalentCount > 0 {
                saveFPUToCoreDataAsBatchInsert(entries: futureCarbEquivalents)
            }
        }
    }

//
//    private func handleFPUCalculations(entries: [CarbsEntry]) {
//        let file = OpenAPS.Monitor.carbHistory
//        var uniqEvents: [CarbsEntry] = []
//
//        let fat = entries.last?.fat ?? 0
//        let protein = entries.last?.protein ?? 0
//
//        if fat > 0 || protein > 0 {
//            // -------------------------- FPU--------------------------------------
//            let interval = settings.settings.minuteInterval // Interval betwwen carbs
//            let timeCap = settings.settings.timeCap // Max Duration
//            let adjustment = settings.settings.individualAdjustmentFactor
//            let delay = settings.settings.delay // Tme before first future carb entry
//            let kcal = protein * 4 + fat * 9
//            let carbEquivalents = (kcal / 10) * adjustment
//            let fpus = carbEquivalents / 10
//            // Duration in hours used for extended boluses with Warsaw Method. Here used for total duration of the computed carbquivalents instead, excluding the configurable delay.
//            var computedDuration = 0
//            switch fpus {
//            case ..<2:
//                computedDuration = 3
//            case 2 ..< 3:
//                computedDuration = 4
//            case 3 ..< 4:
//                computedDuration = 5
//            default:
//                computedDuration = timeCap
//            }
//            // Size of each created carb equivalent if 60 minutes interval
//            var equivalent: Decimal = carbEquivalents / Decimal(computedDuration)
//            // Adjust for interval setting other than 60 minutes
//            equivalent /= Decimal(60 / interval)
//            // Round to 1 fraction digit
//            // equivalent = Decimal(round(Double(equivalent * 10) / 10))
//            let roundedEquivalent: Double = round(Double(equivalent * 10)) / 10
//            equivalent = Decimal(roundedEquivalent)
//            // Number of equivalents
//            var numberOfEquivalents = carbEquivalents / equivalent
//            // Only use delay in first loop
//            var firstIndex = true
//            // New date for each carb equivalent
//            var useDate = entries.last?.actualDate ?? Date()
//            // Group and Identify all FPUs together
//            let fpuID = entries.last?.fpuID ?? ""
//            // Create an array of all future carb equivalents.
//            var futureCarbArray = [CarbsEntry]()
//            while carbEquivalents > 0, numberOfEquivalents > 0 {
//                if firstIndex {
//                    useDate = useDate.addingTimeInterval(delay.minutes.timeInterval)
//                    firstIndex = false
//                } else { useDate = useDate.addingTimeInterval(interval.minutes.timeInterval) }
//
//                let eachCarbEntry = CarbsEntry(
//                    id: UUID().uuidString, createdAt: entries.last?.createdAt ?? Date(), actualDate: useDate,
//                    carbs: equivalent, fat: 0, protein: 0, note: nil,
//                    enteredBy: CarbsEntry.manual, isFPU: true,
//                    fpuID: fpuID
//                )
//                futureCarbArray.append(eachCarbEntry)
//                numberOfEquivalents -= 1
//            }
//            // Save the array
//            if carbEquivalents > 0 {
//                storage.transaction { storage in
//                    storage.append(futureCarbArray, to: file, uniqBy: \.id)
//                    uniqEvents = storage.retrieve(file, as: [CarbsEntry].self)?
//                        .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
//                        .sorted { $0.createdAt > $1.createdAt } ?? []
//                    storage.save(Array(uniqEvents), as: file)
//                }
//
//                // MARK: - save also to core data
//
//                saveFPUToCoreDataAsBatchInsert(entries: futureCarbArray)
//            }
//        }
//    }
//
//    private func storeNormalCarbs(entries: [CarbsEntry]) {
//        let file = OpenAPS.Monitor.carbHistory
//        var uniqEvents: [CarbsEntry] = []
//
//        if let entry = entries.last, entry.carbs > 0 {
//            // uniqEvents = []
//            let onlyCarbs = CarbsEntry(
//                id: entry.id ?? "",
//                createdAt: entry.createdAt,
//                actualDate: entry.actualDate ?? entry.createdAt,
//                carbs: entry.carbs,
//                fat: entry.fat,
//                protein: entry.protein,
//                note: entry.note ?? "",
//                enteredBy: entry.enteredBy ?? "",
//                isFPU: false,
//                fpuID: ""
//            )
//
//            storage.transaction { storage in
//                storage.append(onlyCarbs, to: file, uniqBy: \.id)
//                uniqEvents = storage.retrieve(file, as: [CarbsEntry].self)?
//                    .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
//                    .sorted { $0.createdAt > $1.createdAt } ?? []
//                storage.save(Array(uniqEvents), as: file)
//            }
//        }
//    }

    private func saveCarbsToCoreData(entries: [CarbsEntry]) {
        guard let entry = entries.last, entry.carbs != 0 else { return }

        coredataContext.perform {
            let newItem = CarbEntryStored(context: self.coredataContext)
            newItem.date = entry.actualDate ?? entry.createdAt
            newItem.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            newItem.fat = Double(truncating: NSDecimalNumber(decimal: entry.fat ?? 0))
            newItem.protein = Double(truncating: NSDecimalNumber(decimal: entry.protein ?? 0))
            newItem.id = UUID()
            newItem.isFPU = false
            newItem.isUploadedToNS = false

            do {
                guard self.coredataContext.hasChanges else { return }
                try self.coredataContext.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    private func saveFPUToCoreDataAsBatchInsert(entries: [CarbsEntry]) {
        let commonFPUID =
            UUID() // all fpus should only get ONE id per batch insert to be able to delete them referencing the fpuID
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
            carbEntry.isUploadedToNS = false
            return false // return false to continue
        }
        coredataContext.perform {
            do {
                try self.coredataContext.execute(batchInsert)
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.succeeded) saved fpus to core data")
            } catch {
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.failed) error while saving fpus to core data")
            }
        }
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recent() -> [CarbsEntry] {
        storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self)?.reversed() ?? []
    }

    func deleteCarbs(at uniqueID: String, fpuID: String, complex: Bool) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self) ?? []

            if fpuID != "" {
                if allValues.firstIndex(where: { $0.fpuID == fpuID }) == nil {
                    debug(.default, "Didn't find any carb equivalents to delete. ID to search for: " + fpuID.description)
                } else {
                    allValues.removeAll(where: { $0.fpuID == fpuID })
                    storage.save(allValues, as: OpenAPS.Monitor.carbHistory)
                    broadcaster.notify(CarbsObserver.self, on: processQueue) {
                        $0.carbsDidUpdate(allValues)
                    }
                }
            }

            if fpuID == "" || complex {
                if allValues.firstIndex(where: { $0.id == uniqueID }) == nil {
                    debug(.default, "Didn't find any carb entries to delete. ID to search for: " + uniqueID.description)
                } else {
                    allValues.removeAll(where: { $0.id == uniqueID })
                    storage.save(allValues, as: OpenAPS.Monitor.carbHistory)
                    broadcaster.notify(CarbsObserver.self, on: processQueue) {
                        $0.carbsDidUpdate(allValues)
                    }
                }
            }
        }
    }

    func getCarbsNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.carbsNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return await coredataContext.perform {
            return results.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.manual,
                    bolus: nil,
                    insulin: nil,
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

    func getFPUsNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.fpusNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return await coredataContext.perform {
            return results.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.manual,
                    bolus: nil,
                    insulin: nil,
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
}

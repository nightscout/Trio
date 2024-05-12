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
    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment]
    func deleteCarbs(at uniqueID: String, fpuID: String, complex: Bool)
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    let coredataContext = CoreDataStack.shared.backgroundContext

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ entries: [CarbsEntry]) {
        processQueue.sync {
            self.handleFPUCalculations(entries: entries)
            self.storeNormalCarbs(entries: entries)
            self.saveCarbsToCoreData(entries: entries)
            self.notifyObservers(entries: entries)
        }
    }

    private func handleFPUCalculations(entries: [CarbsEntry]) {
        let file = OpenAPS.Monitor.carbHistory
        var uniqEvents: [CarbsEntry] = []

        let fat = entries.last?.fat ?? 0
        let protein = entries.last?.protein ?? 0

        if fat > 0 || protein > 0 {
            // -------------------------- FPU--------------------------------------
            let interval = settings.settings.minuteInterval // Interval betwwen carbs
            let timeCap = settings.settings.timeCap // Max Duration
            let adjustment = settings.settings.individualAdjustmentFactor
            let delay = settings.settings.delay // Tme before first future carb entry
            let kcal = protein * 4 + fat * 9
            let carbEquivalents = (kcal / 10) * adjustment
            let fpus = carbEquivalents / 10
            // Duration in hours used for extended boluses with Warsaw Method. Here used for total duration of the computed carbquivalents instead, excluding the configurable delay.
            var computedDuration = 0
            switch fpus {
            case ..<2:
                computedDuration = 3
            case 2 ..< 3:
                computedDuration = 4
            case 3 ..< 4:
                computedDuration = 5
            default:
                computedDuration = timeCap
            }
            // Size of each created carb equivalent if 60 minutes interval
            var equivalent: Decimal = carbEquivalents / Decimal(computedDuration)
            // Adjust for interval setting other than 60 minutes
            equivalent /= Decimal(60 / interval)
            // Round to 1 fraction digit
            // equivalent = Decimal(round(Double(equivalent * 10) / 10))
            let roundedEquivalent: Double = round(Double(equivalent * 10)) / 10
            equivalent = Decimal(roundedEquivalent)
            // Number of equivalents
            var numberOfEquivalents = carbEquivalents / equivalent
            // Only use delay in first loop
            var firstIndex = true
            // New date for each carb equivalent
            var useDate = entries.last?.actualDate ?? Date()
            // Group and Identify all FPUs together
            let fpuID = entries.last?.fpuID ?? ""
            // Create an array of all future carb equivalents.
            var futureCarbArray = [CarbsEntry]()
            while carbEquivalents > 0, numberOfEquivalents > 0 {
                if firstIndex {
                    useDate = useDate.addingTimeInterval(delay.minutes.timeInterval)
                    firstIndex = false
                } else { useDate = useDate.addingTimeInterval(interval.minutes.timeInterval) }

                let eachCarbEntry = CarbsEntry(
                    id: UUID().uuidString, createdAt: entries.last?.createdAt ?? Date(), actualDate: useDate,
                    carbs: equivalent, fat: 0, protein: 0, note: nil,
                    enteredBy: CarbsEntry.manual, isFPU: true,
                    fpuID: fpuID
                )
                futureCarbArray.append(eachCarbEntry)
                numberOfEquivalents -= 1
            }
            // Save the array
            if carbEquivalents > 0 {
                storage.transaction { storage in
                    storage.append(futureCarbArray, to: file, uniqBy: \.id)
                    uniqEvents = storage.retrieve(file, as: [CarbsEntry].self)?
                        .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                        .sorted { $0.createdAt > $1.createdAt } ?? []
                    storage.save(Array(uniqEvents), as: file)
                }

                // MARK: - save also to core data

                saveFPUToCoreDataAsBatchInsert(entries: futureCarbArray)
            }
        }
    }

    private func storeNormalCarbs(entries: [CarbsEntry]) {
        let file = OpenAPS.Monitor.carbHistory
        var uniqEvents: [CarbsEntry] = []

        if let entry = entries.last, entry.carbs > 0 {
            // uniqEvents = []
            let onlyCarbs = CarbsEntry(
                id: entry.id ?? "",
                createdAt: entry.createdAt,
                actualDate: entry.actualDate ?? entry.createdAt,
                carbs: entry.carbs,
                fat: nil,
                protein: nil,
                note: entry.note ?? "",
                enteredBy: entry.enteredBy ?? "",
                isFPU: false,
                fpuID: ""
            )

            storage.transaction { storage in
                storage.append(onlyCarbs, to: file, uniqBy: \.id)
                uniqEvents = storage.retrieve(file, as: [CarbsEntry].self)?
                    .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.createdAt > $1.createdAt } ?? []
                storage.save(Array(uniqEvents), as: file)
            }
        }
    }

    private func saveCarbsToCoreData(entries: [CarbsEntry]) {
        guard let entry = entries.last, entry.carbs != 0 else { return }

        coredataContext.perform {
            let newItem = CarbEntryStored(context: self.coredataContext)
            newItem.date = entry.actualDate ?? entry.createdAt
            newItem.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            newItem.id = UUID()
            newItem.isFPU = false
            if self.coredataContext.hasChanges {
                do {
                    try self.coredataContext.save()
                    debugPrint(
                        "Carbs Storage: \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) saved carbs to core data"
                    )
                } catch {
                    debugPrint(
                        "Carbs Storage: \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) error while saving carbs to core data"
                    )
                }
            }
        }
    }

    private func saveFPUToCoreDataAsBatchInsert(entries: [CarbsEntry]) {
        let commonFPUID = UUID() // all fpus should only get ONE id per batch insert to be able to delete them referencing the id
        var entrySlice = ArraySlice(entries) // convert to ArraySlice
        let batchInsert = NSBatchInsertRequest(entity: CarbEntryStored.entity()) { (managedObject: NSManagedObject) -> Bool in
            guard let carbEntry = managedObject as? CarbEntryStored, let entry = entrySlice.popFirst() else {
                return true // return true to stop
            }
            carbEntry.date = entry.actualDate
            carbEntry.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            carbEntry.id = commonFPUID
            carbEntry.isFPU = true
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

    private func notifyObservers(entries: [CarbsEntry]) {
        broadcaster.notify(CarbsObserver.self, on: processQueue) {
            $0.carbsDidUpdate(entries)
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

    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedCarbs, as: [NigtscoutTreatment].self) ?? []

        let eventsManual = recent().filter { $0.enteredBy == CarbsEntry.manual }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsCarbCorrection,
                createdAt: $0.actualDate ?? $0.createdAt,
                enteredBy: CarbsEntry.manual,
                bolus: nil,
                insulin: nil,
                carbs: $0.carbs,
                fat: nil,
                protein: nil,
                foodType: $0.note,
                targetTop: nil,
                targetBottom: nil,
                id: $0.id,
                fpuID: $0.fpuID
            )
        }
        return Array(Set(treatments).subtracting(Set(uploaded)))
    }
}

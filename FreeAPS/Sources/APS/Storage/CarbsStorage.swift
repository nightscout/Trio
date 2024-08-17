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
    func nightscoutTretmentsNotUploaded() -> [NightscoutTreatment]
    func deleteCarbs(at date: Date)
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    let coredataContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    /**
     Processes and stores carbohydrate entries, including handling entries with fat and protein to calculate and distribute future carb equivalents.

     - The function processes fat and protein units (FPUs) by creating carb equivalents for future use.
     - Ensures each carb equivalent is at least 1.0 grams by adjusting the interval if necessary.
     - Stores the actual carbohydrate entries.
     - Saves the data to CoreData for statistical purposes.
     - Notifies observers of the carbohydrate data update.

     - Parameters:
       - entries: An array of `CarbsEntry` objects representing the carbohydrate entries to be processed and stored.
     */
    func storeCarbs(_ entries: [CarbsEntry]) {
        processQueue.sync {
            let file = OpenAPS.Monitor.carbHistory
            var entriesToStore: [CarbsEntry] = []

            guard let lastEntry = entries.last else { return }

            if let fat = lastEntry.fat, let protein = lastEntry.protein, fat > 0 || protein > 0 {
                let (futureCarbArray, carbEquivalents) = processFPU(
                    entries: entries,
                    fat: fat,
                    protein: protein,
                    createdAt: lastEntry.createdAt
                )
                if carbEquivalents > 0 {
                    self.storage.transaction { storage in
                        storage.append(futureCarbArray, to: file, uniqBy: \.id)
                        entriesToStore = storage.retrieve(file, as: [CarbsEntry].self)?
                            .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                            .sorted { $0.createdAt > $1.createdAt } ?? []
                        storage.save(Array(entriesToStore), as: file)
                    }
                }
            }

            if lastEntry.carbs > 0 {
                self.storage.transaction { storage in
                    storage.append(entries, to: file, uniqBy: \.createdAt)
                    entriesToStore = storage.retrieve(file, as: [CarbsEntry].self)?
                        .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                        .sorted { $0.createdAt > $1.createdAt } ?? []
                    storage.save(Array(entriesToStore), as: file)
                }
            }

            var cbs: Decimal = 0
            var carbDate = Date()
            if entries.isNotEmpty {
                cbs = entries[0].carbs
                carbDate = entries[0].createdAt
            }
            if cbs != 0 {
                self.coredataContext.perform {
                    let carbDataForStats = Carbohydrates(context: self.coredataContext)

                    carbDataForStats.date = carbDate
                    carbDataForStats.carbs = cbs as NSDecimalNumber

                    try? self.coredataContext.save()
                }
            }
            broadcaster.notify(CarbsObserver.self, on: processQueue) {
                $0.carbsDidUpdate(entriesToStore)
            }
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
                id: UUID().uuidString, createdAt: useDate,
                carbs: carbEquivalentSize, fat: 0, protein: 0, note: nil,
                enteredBy: CarbsEntry.manual, isFPU: true,
                fpuID: fpuID
            )
            futureCarbArray.append(eachCarbEntry)
            numberOfEquivalents -= 1
        }

        return (futureCarbArray, carbEquivalents)
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recent() -> [CarbsEntry] {
        storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self)?.reversed() ?? []
    }

    func deleteCarbs(at date: Date) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self) ?? []

            guard let entryIndex = allValues.firstIndex(where: { $0.createdAt == date }) else {
                return
            }

            // If deleteing a FPUs remove all of those with the same ID
            if allValues[entryIndex].isFPU != nil, allValues[entryIndex].isFPU ?? false {
                let fpuString = allValues[entryIndex].fpuID
                allValues.removeAll(where: { $0.fpuID == fpuString })
                storage.save(allValues, as: OpenAPS.Monitor.carbHistory)
                broadcaster.notify(CarbsObserver.self, on: processQueue) {
                    $0.carbsDidUpdate(allValues)
                }
            } else {
                allValues.remove(at: entryIndex)
                storage.save(allValues, as: OpenAPS.Monitor.carbHistory)
                broadcaster.notify(CarbsObserver.self, on: processQueue) {
                    $0.carbsDidUpdate(allValues)
                }
            }
        }
    }

    func nightscoutTretmentsNotUploaded() -> [NightscoutTreatment] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedPumphistory, as: [NightscoutTreatment].self) ?? []

        let eventsManual = recent().filter { $0.enteredBy == CarbsEntry.manual }
        let treatments = eventsManual.map {
            NightscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsCarbCorrection,
                createdAt: $0.createdAt,
                enteredBy: CarbsEntry.manual,
                bolus: nil,
                insulin: nil,
                carbs: $0.carbs,
                fat: $0.fat,
                protein: $0.protein,
                foodType: $0.note,
                targetTop: nil,
                targetBottom: nil
            )
        }
        return Array(Set(treatments).subtracting(Set(uploaded)))
    }
}

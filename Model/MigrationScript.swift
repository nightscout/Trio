import CoreData
import Foundation

class JSONImporter {
    private let context: NSManagedObjectContext
    private let fileManager = FileManager.default

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func importPumpHistoryIfNeeded() async {
        let userDefaultsKey = "pumpHistoryImported"
        let hasImported = UserDefaults.standard.bool(forKey: userDefaultsKey)

        guard !hasImported else {
            debugPrint("Pump history already imported. Skipping import.")
            return
        }

        do {
            // Get filepath
            guard let filePath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(OpenAPS.Monitor.pumpHistory),
                fileManager.fileExists(atPath: filePath.path)
            else {
                debugPrint("Pump history file not found at path \(OpenAPS.Monitor.pumpHistory)")
                return
            }

            // Read JSON and decode
            let data = try Data(contentsOf: filePath)
            let pumpEvents = try JSONDecoder().decode([PumpEventDTO].self, from: data)

            // Save to Core Data
            await context.perform {
                for event in pumpEvents {
                    self.storePumpEventFromDTO(event)
                }

                do {
                    guard self.context.hasChanges else { return }
                    try self.context.save()
                    debugPrint("\(DebuggingIdentifiers.succeeded) Pump history successfully imported into Core Data.")
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Failed to save pump history to Core Data: \(error)")
                }
            }

            // Delete JSON
            try fileManager.removeItem(at: filePath)
            debugPrint("pumphistory.json deleted after successful import.")

            // Update UserDefaults flag
            UserDefaults.standard.set(true, forKey: userDefaultsKey)
        } catch {
            debugPrint("Error importing pump history: \(error)")
        }
    }

    private func storePumpEventFromDTO(_ event: PumpEventDTO) {
        // Map each type of PumpEventDTO to its corresponding Core Data model.
        switch event {
        case let .bolus(bolusDTO):
            let pumpEvent = PumpEventStored(context: context)
            pumpEvent.id = bolusDTO.id
            pumpEvent.timestamp = ISO8601DateFormatter().date(from: bolusDTO.timestamp)
            pumpEvent.type = bolusDTO._type

            let bolus = BolusStored(context: context)
            bolus.amount = NSDecimalNumber(value: bolusDTO.amount)
            bolus.isExternal = bolusDTO.isExternal
            bolus.isSMB = bolusDTO.isSMB ?? false
            pumpEvent.bolus = bolus

        case let .tempBasal(tempBasalDTO):
            let pumpEvent = PumpEventStored(context: context)
            pumpEvent.id = tempBasalDTO.id
            pumpEvent.timestamp = ISO8601DateFormatter().date(from: tempBasalDTO.timestamp)
            pumpEvent.type = tempBasalDTO._type

            let tempBasal = TempBasalStored(context: context)
            tempBasal.tempType = tempBasalDTO.temp
            tempBasal.rate = NSDecimalNumber(value: tempBasalDTO.rate)
            pumpEvent.tempBasal = tempBasal

        case let .tempBasalDuration(tempBasalDurationDTO):
            let pumpEvent = PumpEventStored(context: context)
            pumpEvent.id = tempBasalDurationDTO.id
            pumpEvent.timestamp = ISO8601DateFormatter().date(from: tempBasalDurationDTO.timestamp)
            pumpEvent.type = tempBasalDurationDTO._type

            let tempBasal = TempBasalStored(context: context)
            tempBasal.duration = Int16(tempBasalDurationDTO.duration)
            pumpEvent.tempBasal = tempBasal
        case .pumpSuspend:
            return
        }
    }

    func importCarbHistoryIfNeeded() async {
        let userDefaultsKey = "carbHistoryImported"
        let hasImported = UserDefaults.standard.bool(forKey: userDefaultsKey)

        guard !hasImported else {
            debugPrint("Carb history already imported. Skipping import.")
            return
        }

        do {
            // Get filepath
            guard let filePath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(OpenAPS.Monitor.carbHistory),
                fileManager.fileExists(atPath: filePath.path)
            else {
                debugPrint("Carb history file not found at path \(OpenAPS.Monitor.carbHistory)")
                return
            }

            // Read JSON and decode
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // Decode JSON
            let carbEntries = try decoder.decode([CarbEntryDTO].self, from: data)

            // Save to Core Data
            await context.perform {
                for entryDTO in carbEntries {
                    self.storeCarbEntryFromDTO(entryDTO)
                }

                do {
                    guard self.context.hasChanges else { return }
                    try self.context.save()
                    debugPrint("\(DebuggingIdentifiers.succeeded) Carb history successfully imported into Core Data.")
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Failed to save carb history to Core Data: \(error)")
                }
            }

            // Delete JSON
            try fileManager.removeItem(at: filePath)
            debugPrint("carbHistory.json deleted after successful import.")

            // Update UserDefaults flag
            UserDefaults.standard.set(true, forKey: userDefaultsKey)
        } catch {
            debugPrint("Error importing carb history: \(error)")
        }
    }

    private func storeCarbEntryFromDTO(_ entryDTO: CarbEntryDTO) {
        let carbEntry = CarbEntryStored(context: context)
        carbEntry.id = entryDTO.id ?? UUID()
        carbEntry.carbs = entryDTO.carbs
        carbEntry.date = entryDTO.date ?? Date()
        carbEntry.fat = entryDTO.fat ?? 0.0
        carbEntry.protein = entryDTO.protein ?? 0.0
        carbEntry.isFPU = entryDTO.isFPU ?? false
        carbEntry.note = entryDTO.note
        carbEntry.isUploadedToNS = false
        carbEntry.isUploadedToHealth = false
        carbEntry.isUploadedToTidepool = false
    }
}

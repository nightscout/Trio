import CoreData
import Foundation
import Swinject

protocol OverrideStorage {
    func loadLatestOverrideConfigurations(fetchLimit: Int) async -> [NSManagedObjectID]
    func fetchForOverridePresets() async -> [NSManagedObjectID]
    func calculateTarget(override: OverrideStored) -> Decimal
    func storeOverride(override: Override) async
    func copyRunningOverride(_ override: OverrideStored) async
    func deleteOverridePreset(_ objectID: NSManagedObjectID) async
    func getOverridesNotYetUploadedToNightscout() async -> [NightscoutExercise]
    func getOverrideRunsNotYetUploadedToNightscout() async -> [NightscoutExercise]
}

final class BaseOverrideStorage: OverrideStorage, Injectable {
    @Injected() private var settingsManager: SettingsManager!

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yy HH:mm"
        return df
    }

    func loadLatestOverrideConfigurations(fetchLimit: Int) async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.lastActiveOverride,
            key: "orderPosition",
            ascending: true,
            fetchLimit: fetchLimit
        )

        return await backgroundContext.perform {
            return results.map(\.objectID)
        }
    }

    /// Returns the NSManagedObjectID of the Override Presets
    func fetchForOverridePresets() async -> [NSManagedObjectID] {
        let result = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.allOverridePresets,
            key: "orderPosition",
            ascending: true
        )

        return await backgroundContext.perform {
            return result.map(\.objectID)
        }
    }

    @MainActor func calculateTarget(override: OverrideStored) -> Decimal {
        guard let overrideTarget = override.target, overrideTarget != 0 else {
            return 100 // default
        }
        return overrideTarget.decimalValue
    }

    func storeOverride(override: Override) async {
        var presetCount = -1
        if override.isPreset {
            let presets = await fetchForOverridePresets()
            presetCount = presets.count
        }

        await backgroundContext.perform {
            let newOverride = OverrideStored(context: self.backgroundContext)

            // override key meta data
            if !override.name.isEmpty {
                newOverride.name = override.name
            } else {
                let formattedDate = self.dateFormatter.string(from: Date())
                newOverride.name = "Preset <\(formattedDate)>"
            }
            newOverride.id = UUID().uuidString
            newOverride.date = override.date
            newOverride.isPreset = override.isPreset
            newOverride.isUploadedToNS = false

            // Assign orderPosition if it's a preset and presetCount is valid
            if override.isPreset, presetCount > -1 {
                newOverride.orderPosition = Int16(presetCount + 1) // Ensure type matches Core Data model
            }

            // override metrics
            newOverride.duration = override.duration as NSDecimalNumber
            newOverride.indefinite = override.indefinite
            newOverride.percentage = override.percentage
            newOverride.enabled = override.enabled
            newOverride.smbIsOff = override.smbIsOff
            if override.overrideTarget {
                newOverride.target = (
                    self.settingsManager.settings.units == .mmolL ? override.target.asMgdL : override.target
                ) as NSDecimalNumber
            } else {
                newOverride.target = 0
            }
            if override.advancedSettings {
                newOverride.advancedSettings = true

                if !override.isfAndCr {
                    newOverride.isfAndCr = false
                    newOverride.isf = override.isf
                    newOverride.cr = override.cr
                } else {
                    newOverride.isfAndCr = true
                }

                if override.smbIsAlwaysOff {
                    newOverride.smbIsAlwaysOff = true
                    newOverride.start = override.start as NSDecimalNumber
                    newOverride.end = override.end as NSDecimalNumber
                } else {
                    newOverride.smbIsAlwaysOff = false
                }

                newOverride.smbMinutes = override.smbMinutes as NSDecimalNumber
                newOverride.uamMinutes = override.uamMinutes as NSDecimalNumber
            }

            do {
                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Override Preset to Core Data with error: \(error.userInfo)"
                )
            }
        }
    }

    // Copy the current Override if it is a RUNNING Preset
    /// otherwise we would edit the Preset
    @MainActor func copyRunningOverride(_ override: OverrideStored) async {
        let newOverride = OverrideStored(context: viewContext)
        newOverride.duration = override.duration
        newOverride.indefinite = override.indefinite
        newOverride.percentage = override.percentage
        newOverride.smbIsOff = override.smbIsOff
        newOverride.name = override.name
        newOverride.isPreset = false // no Preset
        newOverride.date = Date()
        newOverride.enabled = override.enabled
        newOverride.target = override.target
        newOverride.advancedSettings = override.advancedSettings
        newOverride.isfAndCr = override.isfAndCr
        newOverride.isf = override.isf
        newOverride.cr = override.cr
        newOverride.smbIsAlwaysOff = override.smbIsAlwaysOff
        newOverride.start = override.start
        newOverride.end = override.end
        newOverride.smbMinutes = override.smbMinutes
        newOverride.uamMinutes = override.uamMinutes

        await viewContext.perform {
            do {
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to copy Override with error: \(error.userInfo)"
                )
            }
        }
    }

    /// marked as MainActor to be able to publish changes from the background
    /// - Parameter: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
    @MainActor func deleteOverridePreset(_ objectID: NSManagedObjectID) async {
        await CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }

    func getOverridesNotYetUploadedToNightscout() async -> [NightscoutExercise] {
        let fetchedOverrides = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.lastActiveOverrideNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return await backgroundContext.perform {
            return fetchedOverrides.map { override in
                let duration = override.indefinite ? 1440 : override.duration ?? 0 // 1440 min = 1 day
                return NightscoutExercise(
                    duration: Int(truncating: duration),
                    eventType: OverrideStored.EventType.nsExercise,
                    createdAt: override.date ?? Date(),
                    enteredBy: NightscoutExercise.local,
                    notes: override.name ?? "Custom Override"
                )
            }
        }
    }

    func getOverrideRunsNotYetUploadedToNightscout() async -> [NightscoutExercise] {
        let fetchedOverrideRuns = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideRunStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate(
                format: "startDate >= %@ AND isUploadedToNS == %@",
                Date.oneDayAgo as NSDate,
                false as NSNumber
            ),
            key: "startDate",
            ascending: false
        )

        return await backgroundContext.perform {
            return fetchedOverrideRuns.map { overrideRun in
                var durationInMinutes = (overrideRun.endDate?.timeIntervalSince(overrideRun.startDate ?? Date()) ?? 1) / 60
                durationInMinutes = durationInMinutes < 1 ? 1 : durationInMinutes
                return NightscoutExercise(
                    duration: Int(durationInMinutes),
                    eventType: OverrideStored.EventType.nsExercise,
                    createdAt: (overrideRun.startDate ?? overrideRun.override?.date) ?? Date(),
                    enteredBy: NightscoutExercise.local,
                    notes: overrideRun.override?.name ?? "Custom Override"
                )
            }
        }
    }
}

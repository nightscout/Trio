import CoreData
import Foundation
import Swinject

protocol OverrideStorage {
    func fetchLastCreatedOverride() async throws -> [NSManagedObjectID]
    func loadLatestOverrideConfigurations(fetchLimit: Int) async throws -> [NSManagedObjectID]
    func fetchForOverridePresets() async throws -> [NSManagedObjectID]
    func calculateTarget(override: OverrideStored) -> Decimal
    func storeOverride(override: Override) async throws
    func copyRunningOverride(_ override: OverrideStored) async -> NSManagedObjectID
    func deleteOverridePreset(_ objectID: NSManagedObjectID) async
    func getOverridesNotYetUploadedToNightscout() async throws -> [NightscoutExercise]
    func getOverrideRunsNotYetUploadedToNightscout() async throws -> [NightscoutExercise]
    func checkIfShouldDeleteNightscoutOverrideEntry(
        forCreatedAt createdAtString: String,
        newDuration: Int?,
        using nightscout: NightscoutAPI
    ) async throws
    func getPresetOverridesForNightscout() async throws -> [NightscoutPresetOverride]
    func fetchLatestActiveOverride() async throws -> NSManagedObjectID?
}

final class BaseOverrideStorage: @preconcurrency OverrideStorage, Injectable {
    @Injected() private var settingsManager: SettingsManager!

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let context: NSManagedObjectContext

    init(resolver: Resolver, context: NSManagedObjectContext? = nil) {
        self.context = context ?? CoreDataStack.shared.newTaskContext()
        injectServices(resolver)
    }

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.current
        return dateFormatter
    }

    func fetchLastCreatedOverride() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate(
                format: "date >= %@",
                Date.oneDayAgo as NSDate
            ),
            key: "date",
            ascending: false,
            fetchLimit: 1
        )

        return try await context.perform {
            guard let fetchedResults = results as? [OverrideStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    func loadLatestOverrideConfigurations(fetchLimit: Int) async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveOverride,
            key: "orderPosition",
            ascending: true,
            fetchLimit: fetchLimit
        )

        return try await context.perform {
            guard let fetchedResults = results as? [OverrideStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    /// Returns the NSManagedObjectID of the Override Presets
    func fetchForOverridePresets() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.allOverridePresets,
            key: "orderPosition",
            ascending: true
        )

        return try await context.perform {
            guard let fetchedResults = results as? [OverrideStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor func calculateTarget(override: OverrideStored) -> Decimal {
        guard let overrideTarget = override.target, overrideTarget != 0 else {
            return 0
        }
        return overrideTarget.decimalValue
    }

    func storeOverride(override: Override) async throws {
        var presetCount = -1
        if override.isPreset {
            let presets = try await fetchForOverridePresets()
            presetCount = presets.count
        }

        try await context.perform {
            let newOverride = OverrideStored(context: self.context)

            // override key meta data
            if !override.name.isEmpty {
                newOverride.name = override.name
            } else {
                let formattedDate = self.dateFormatter.string(from: Date())
                newOverride.name = "Override \(formattedDate)"
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
            newOverride.isfAndCr = override.isfAndCr
            newOverride.isf = override.isf
            newOverride.cr = override.cr
            newOverride.enabled = override.enabled
            newOverride.smbIsOff = override.smbIsOff
            if override.overrideTarget {
                newOverride.target = override.target as NSDecimalNumber
            } else {
                newOverride.target = 0
            }
            if override.advancedSettings {
                newOverride.advancedSettings = true

                newOverride.smbMinutes = override.smbMinutes as NSDecimalNumber
                newOverride.uamMinutes = override.uamMinutes as NSDecimalNumber
            }

            if override.smbIsScheduledOff {
                newOverride.smbIsScheduledOff = true
                newOverride.start = override.start as NSDecimalNumber
                newOverride.end = override.end as NSDecimalNumber
            } else {
                newOverride.smbIsScheduledOff = false
            }

            guard self.context.hasChanges else { return }
            try self.context.save()
        }
    }

    // Copy the current Override if it is a RUNNING Preset
    /// otherwise we would edit the Preset
    @MainActor func copyRunningOverride(_ override: OverrideStored) async -> NSManagedObjectID {
        let newOverride = OverrideStored(context: viewContext)
        newOverride.duration = override.duration
        newOverride.indefinite = override.indefinite
        newOverride.percentage = override.percentage
        newOverride.smbIsOff = override.smbIsOff
        newOverride.name = override.name
        newOverride.isPreset = false // no Preset
        newOverride.date = override.date
        newOverride.enabled = override.enabled
        newOverride.target = override.target
        newOverride.advancedSettings = override.advancedSettings
        newOverride.isfAndCr = override.isfAndCr
        newOverride.isf = override.isf
        newOverride.cr = override.cr
        newOverride.smbIsScheduledOff = override.smbIsScheduledOff
        newOverride.start = override.start
        newOverride.end = override.end
        newOverride.smbMinutes = override.smbMinutes
        newOverride.uamMinutes = override.uamMinutes
        newOverride.isUploadedToNS = true // set to true to avoid getting duplicate entries on NS

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

        return newOverride.objectID
    }

    /// - Parameter: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
    func deleteOverridePreset(_ objectID: NSManagedObjectID) async {
        // Use injected context if available, otherwise create new task context
        let taskContext = context != CoreDataStack.shared.newTaskContext()
            ? context
            : CoreDataStack.shared.newTaskContext()

        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "deleteOverride"

        await taskContext.perform {
            do {
                guard let override = try taskContext.existingObject(with: objectID) as? OverrideStored else {
                    debugPrint("Override for batch delete not found. \(DebuggingIdentifiers.failed)")
                    return
                }

                taskContext.delete(override)

                guard taskContext.hasChanges else { return }
                try taskContext.save()

                debugPrint(
                    "OverrideStorage: \(#function) \(DebuggingIdentifiers.succeeded) deleted override from core data"
                )
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error deleting override: \(error)")
            }
        }
    }

    func getOverridesNotYetUploadedToNightscout() async throws -> [NightscoutExercise] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveAdjustmentNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedOverrides = results as? [OverrideStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedOverrides.map { override in
                let duration = override.indefinite ? 43200 : override.duration ?? 0 // 43200 min = 30 days
                return NightscoutExercise(
                    duration: Int(truncating: duration),
                    eventType: OverrideStored.EventType.nsExercise,
                    createdAt: override.date ?? Date(),
                    enteredBy: NightscoutExercise.local,
                    notes: override.name ?? String(localized: "Custom Override"),
                    id: UUID(uuidString: override.id ?? UUID().uuidString)
                )
            }
        }
    }

    func getOverrideRunsNotYetUploadedToNightscout() async throws -> [NightscoutExercise] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideRunStored.self,
            onContext: context,
            predicate: NSPredicate(
                format: "startDate >= %@ AND isUploadedToNS == %@",
                Date.oneDayAgo as NSDate,
                false as NSNumber
            ),
            key: "startDate",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedOverrideRuns = results as? [OverrideRunStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedOverrideRuns.map { overrideRun in
                var durationInMinutes = (overrideRun.endDate?.timeIntervalSince(overrideRun.startDate ?? Date()) ?? 1) / 60
                durationInMinutes = durationInMinutes < 1 ? 1 : durationInMinutes
                return NightscoutExercise(
                    duration: Int(durationInMinutes),
                    eventType: OverrideStored.EventType.nsExercise,
                    createdAt: (overrideRun.startDate ?? overrideRun.override?.date) ?? Date(),
                    enteredBy: NightscoutExercise.local,
                    notes: overrideRun.name ?? String(localized: "Custom Override"),
                    id: overrideRun.id
                )
            }
        }
    }

    /// This check is needed to force re-rendering of overrides in the Nightscout main chart
    /// if the override duration has changed (cancelled, customized or replaced with other override),
    /// since just updating durations in existing entries doesn't trigger re-rendering.
    func checkIfShouldDeleteNightscoutOverrideEntry(
        forCreatedAt createdAtString: String,
        newDuration: Int?,
        using nightscout: NightscoutAPI
    ) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let jsonDate = formatter.date(from: createdAtString) else {
            debug(.nightscout, "Could not parse override created_at string: \(createdAtString)")
            return
        }

        /// Define a tolerance window (in seconds)
        /// This is neccessary to handle small rounding/conversion time differences
        /// when comparing dates between core data and NightscoutExercise json
        let tolerance: TimeInterval = 0.1
        let lowerBound = jsonDate.addingTimeInterval(-tolerance)
        let upperBound = jsonDate.addingTimeInterval(tolerance)

        /// Build a predicate to fetch a stored override (from OverrideStored) whose date is within the tolerance window.
        let predicate = NSPredicate(format: "date >= %@ AND date <= %@", lowerBound as NSDate, upperBound as NSDate)
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: predicate,
            key: "date",
            ascending: false
        )

        let storedOverride: NightscoutExercise? = await context.perform {
            guard let fetched = results as? [OverrideStored],
                  let record = fetched.first,
                  let recordDate = record.date else { return nil }
            let duration = record.indefinite ? 43200 : record.duration ?? 0
            return NightscoutExercise(
                duration: Int(truncating: duration),
                eventType: OverrideStored.EventType.nsExercise,
                createdAt: recordDate,
                enteredBy: NightscoutExercise.local,
                notes: record.name ?? String(localized: "Custom Override"),
                id: UUID(uuidString: record.id ?? UUID().uuidString)
            )
        }

        if let existing = storedOverride {
            // Only delete existing nightscout entries if the durations differ.
            if let existingDuration = existing.duration, let newDuration = newDuration, existingDuration != newDuration {
                try await nightscout.deleteNightscoutOverride(withCreatedAt: createdAtString)
            }
        }
    }

    func getPresetOverridesForNightscout() async throws -> [NightscoutPresetOverride] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.allOverridePresets,
            key: "orderPosition",
            ascending: true
        )

        return try await context.perform {
            guard let fetchedResults = results as? [OverrideStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map { overrideStored in
                let duration = overrideStored.duration as? Decimal != 0 ? overrideStored.duration as? Decimal : nil
                let percentage = overrideStored.percentage != 0 ? overrideStored.percentage : nil
                let target = (overrideStored.target as? Decimal) != 0 ? overrideStored.target as? Decimal : nil

                return NightscoutPresetOverride(
                    name: overrideStored.name ?? "",
                    duration: duration,
                    percentage: percentage,
                    target: target
                )
            }
        }
    }

    func fetchLatestActiveOverride() async throws -> NSManagedObjectID? {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveOverride,
            key: "date",
            ascending: false,
            fetchLimit: 1
        )

        return try await context.perform {
            guard let fetchedResults = results as? [OverrideStored]
            else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.first?.objectID
        }
    }
}

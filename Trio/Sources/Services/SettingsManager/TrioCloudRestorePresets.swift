import CoreData
import Foundation

extension TrioCloudSettingsRestore {
    static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func readDefaults(defaults: UserDefaults = .standard) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for key in TrioSettingsBackup.AppConfiguration.keys {
            if let value = defaults.object(forKey: key) {
                result[key] = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
            }
        }
        return result
    }

    static func verifyPresets(
        _ expected: TrioSettingsBackup.Presets,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let actual = try await TrioSettingsBackup.readPresets(context: context ?? CoreDataStack.shared.newTaskContext())
        let sorted = TrioSettingsBackup.Presets(
            overrides: try TrioSettingsBackup.stableSort(expected.overrides),
            tempTargets: try TrioSettingsBackup.stableSort(expected.tempTargets),
            meals: try TrioSettingsBackup.stableSort(expected.meals)
        )
        guard try canonical(actual) == canonical(sorted) else { throw BackupError.restoreFailed }
    }

    /// Replace preset templates in one save, preserving historical and active adjustments.
    static func replacePresets(with source: TrioSettingsBackup.Presets, context: NSManagedObjectContext? = nil) async throws {
        let context = context ?? CoreDataStack.shared.newTaskContext()
        try await context.perform {
            let previousAuthor = context.transactionAuthor
            defer { context.transactionAuthor = previousAuthor }
            context.transactionAuthor = "TrioCloudRestore"
            do {
                let overrideRequest = OverrideStored.fetchRequest()
                overrideRequest.predicate = NSPredicate(format: "isPreset == YES")
                for row in try context.fetch(overrideRequest) {
                    if row.overrideRun != nil {
                        // Retire the template to preserve historical runs' configuration relationship.
                        row.isPreset = false
                        row.enabled = false
                    } else { context.delete(row) }
                }

                let targetRequest = TempTargetStored.fetchRequest()
                targetRequest.predicate = NSPredicate(format: "isPreset == YES")
                for row in try context.fetch(targetRequest) {
                    if row.tempTargetRun != nil {
                        row.isPreset = false
                        row.enabled = false
                    } else { context.delete(row) }
                }

                for row in try context.fetch(MealPresetStored.fetchRequest()) { context.delete(row) }

                for preset in source.overrides {
                    let row = OverrideStored(context: context)
                    row.id = UUID().uuidString
                    row.name = preset.name
                    row.date = .distantPast
                    row.isPreset = true
                    row.enabled = false
                    row.isUploadedToNS = false
                    row.orderPosition = preset.order
                    row.percentage = preset.percentage
                    row.duration = preset.duration.map(NSDecimalNumber.init(decimal:))
                    row.indefinite = preset.indefinite
                    row.target = preset.target.map(NSDecimalNumber.init(decimal:))
                    row.isf = preset.isf
                    row.cr = preset.cr
                    row.isfAndCr = preset.isfAndCr
                    row.advancedSettings = preset.advancedSettings
                    row.smbIsScheduledOff = preset.smbIsScheduledOff
                    row.smbIsOff = preset.smbIsOff
                    row.smbMinutes = preset.smbMinutes.map(NSDecimalNumber.init(decimal:))
                    row.uamMinutes = preset.uamMinutes.map(NSDecimalNumber.init(decimal:))
                    row.start = preset.start.map(NSDecimalNumber.init(decimal:))
                    row.end = preset.end.map(NSDecimalNumber.init(decimal:))
                }

                for preset in source.tempTargets {
                    let row = TempTargetStored(context: context)
                    row.id = UUID()
                    row.name = preset.name
                    row.date = .distantPast
                    row.isPreset = true
                    row.enabled = false
                    row.isUploadedToNS = false
                    row.orderPosition = preset.order
                    row.duration = preset.duration.map(NSDecimalNumber.init(decimal:))
                    row.target = preset.target.map(NSDecimalNumber.init(decimal:))
                    row.halfBasalTarget = preset.halfBasalTarget.map(NSDecimalNumber.init(decimal:))
                }

                for preset in source.meals {
                    let row = MealPresetStored(context: context)
                    row.dish = preset.dish
                    row.carbs = preset.carbs.map(NSDecimalNumber.init(decimal:))
                    row.fat = preset.fat.map(NSDecimalNumber.init(decimal:))
                    row.protein = preset.protein.map(NSDecimalNumber.init(decimal:))
                }
                if context.hasChanges { try context.save() }
            } catch {
                // Clear failed mutations before recovery or retry reuses this context.
                context.rollback()
                throw error
            }
        }
    }
}

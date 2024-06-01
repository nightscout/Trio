import CoreData
import Foundation
import SwiftDate
import Swinject

/// Observer to register to be informed by a change in the current override
protocol OverrideObserver {
    func overrideDidUpdate(_ targets: [OverrideProfile?], current: OverrideProfile?)
}

protocol OverrideStorage {
    func storeOverride(_ targets: [OverrideProfile])
    func storeOverridePresets(_ targets: [OverrideProfile])
    func presets() -> [OverrideProfile]
    func syncDate() -> Date
    func recent() -> [OverrideProfile?]
    //  func nightscoutTretmentsNotUploaded() -> [NightscoutTreatment]
    func current() -> OverrideProfile?
    func cancelCurrentOverride() -> Decimal?
    func applyOverridePreset(_ presetId: String) -> Date?
    func deleteOverridePreset(_ presetId: String)
}

/// Class to manage the store of override and override preset
final class BaseOverrideStorage: OverrideStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseOverrideStorage.processQueue")
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    let coredataContext: NSManagedObjectContext
    private var lastCurrentOverride: OverrideProfile?

    init(
        resolver: Resolver,
        managedObjectContext: NSManagedObjectContext = CoreDataStack.shared.persistentContainer.viewContext
    ) {
        coredataContext = managedObjectContext
        injectServices(resolver)
    }

    /// Convert a override Preset Core Data as a Override Profil
    /// - Parameter preset: a override preset in Core Data
    /// - Returns: A override  in Override Profil structure
    private func OverridePresetToOverrideProfile(_ preset: OverridePresets) -> OverrideProfile {
        OverrideProfile(
            id: preset.id ?? UUID().uuidString,
            name: preset.name,
            duration: preset.duration as Decimal?,
            indefinite: preset.indefinite,
            percentage: preset.percentage,
            target: preset.target as Decimal?,
            advancedSettings: preset.advancedSettings,
            smbIsOff: preset.smbIsOff,
            isfAndCr: preset.isfAndCr,
            isf: preset.isf,
            cr: preset.cr,
            smbIsScheduledOff: preset.smbIsScheduledOff,
            start: preset.start as Decimal?,
            end: preset.end as Decimal?,
            smbMinutes: preset.smbMinutes as Decimal?,
            uamMinutes: preset.uamMinutes as Decimal?,
            enteredBy: OverrideProfile.manual,
            reason: ""
        )
    }

    /// Convert a override  Core Data as a Override Profil
    /// - Parameter preset: a override  in Core Data
    /// - Returns: A override  in Override Profil structure
    private func OverrideToOverrideProfile(_ preset: Override) -> OverrideProfile {
        OverrideProfile(
            id: preset.id ?? UUID().uuidString,
            name: preset.name == "" ? nil : preset.name,
            createdAt: preset.date,
            duration: preset.duration as Decimal?,
            indefinite: preset.indefinite,
            percentage: preset.percentage,
            target: preset.target as Decimal?,
            advancedSettings: preset.advancedSettings,
            smbIsOff: preset.smbIsOff,
            isfAndCr: preset.isfAndCr,
            isf: preset.isf,
            cr: preset.cr,
            smbIsScheduledOff: preset.smbIsScheduledOff,
            start: preset.start as Decimal?,
            end: preset.end as Decimal?,
            smbMinutes: preset.smbMinutes as Decimal?,
            uamMinutes: preset.uamMinutes as Decimal?,
            enteredBy: OverrideProfile.manual,
            reason: ""
        )
    }

    /// Fetch all override presets available in storage core data
    /// - Returns: List of override Presets as Override Profil structure
    func presets() -> [OverrideProfile] {
        fetchOverridePreset().compactMap {
            OverridePresetToOverrideProfile($0)
        }
    }

    /// Fetch all override presets available in storage core data
    /// - Returns: List of override Presets in core data structure
    private func fetchOverridePreset() -> [OverridePresets] {
        coredataContext.performAndWait {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            let sortOverride = NSSortDescriptor(key: "name", ascending: true)
            requestPresets.sortDescriptors = [sortOverride]
            let results = try? self.coredataContext.fetch(requestPresets)
            return results ?? []
        }
    }

    /// delete a preset override
    /// - Parameter presetId: the identifier of the preset override
    func deleteOverridePreset(_ presetId: String) {
        coredataContext.performAndWait {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "id == %@", presetId
            )
            let results = try? self.coredataContext.fetch(requestPresets)
            if let deleteObject = results?.first {
                self.coredataContext.delete(deleteObject)
            }
        }
    }

    /// Store new or updated override target
    /// - Parameter targets: List of new or updated override
    func storeOverride(_ targets: [OverrideProfile]) {
        // if recent, close it before apply new override
        if current() != nil {
            _ = cancelCurrentOverride()
        }
        storeOverride(targets, isPresets: false)
    }

    /// Store override preset in Core Data
    /// - Parameter targets: List of new or updated override preset
    func storeOverridePresets(_ targets: [OverrideProfile]) {
        storeOverride(targets, isPresets: true)
    }

    /// store overrides in Core Data and eventually update the current override event
    /// - Parameters:
    ///   - targets: List of new or updated override as a preset or as a target
    ///   - isPresets: definied if targerts is a override preset (true).
    private func storeOverride(_ targets: [OverrideProfile], isPresets: Bool) {
        // store in preset override
        // processQueue.sync {
        if isPresets {
            let listOverridePresets = fetchOverridePreset()
            _ = targets.compactMap { preset in
                // find if existing or create a new one
                let save = listOverridePresets
                    .first(where: { $0.id == preset.id }) ?? OverridePresets(context: coredataContext)
                save.id = preset.id
                save.name = preset.name
                save.end = preset.end as NSDecimalNumber?
                save.start = preset.start as NSDecimalNumber?
                save.advancedSettings = preset.advancedSettings ?? false
                save.cr = preset.cr ?? false
                save.duration = preset.duration as NSDecimalNumber?
                save.indefinite = preset.indefinite ?? true
                save.isf = preset.isf ?? false
                save.isfAndCr = preset.isfAndCr ?? false
                save.percentage = preset.percentage ?? 100.0
                save.smbIsScheduledOff = preset.smbIsScheduledOff ?? false
                save.smbIsOff = preset.smbIsOff ?? false
                save.smbMinutes = (preset.smbMinutes ?? settingsManager.preferences.maxSMBBasalMinutes) as NSDecimalNumber?
                save.uamMinutes = (preset.uamMinutes ?? settingsManager.preferences.maxUAMSMBBasalMinutes) as NSDecimalNumber?
                save.target = preset.target as NSDecimalNumber?
                return save
            }

            coredataContext.performAndWait {
                do {
                    try coredataContext.save()
                } catch {
                    debug(.openAPS, "Error saving context : \(error)")
                }
            }

        } else {
            _ = targets.compactMap { target in
                // determine if isenable
                var enabled: Bool = false
                let now = Date()
                if let indefinite = target.indefinite, indefinite, target.duration == nil {
                    enabled = true
                } else if
                    let duration = target.duration as Decimal?,
                    let date = target.createdAt,
                    (now.timeIntervalSinceReferenceDate - date.timeIntervalSinceReferenceDate).minutes < Double(duration),
                    date <= now,
                    duration != 0
                {
                    enabled = true
                }
                // update if existing or create
                let save = fetchOverrideById(id: target.id) ?? Override(context: coredataContext)

                save.id = target.id
                save.date = target.createdAt ?? Date()
                save.name = target.name ?? ""
                save.end = target.end as NSDecimalNumber?
                save.start = target.start as NSDecimalNumber?
                save.advancedSettings = target.advancedSettings ?? false
                save.cr = target.cr ?? false
                save.duration = target.duration as NSDecimalNumber?
                save.indefinite = target.indefinite ?? true
                save.isf = target.isf ?? false
                save.isfAndCr = target.isfAndCr ?? false
                save.percentage = target.percentage ?? 100.0
                save.smbIsScheduledOff = target.smbIsScheduledOff ?? false
                save.smbIsOff = target.smbIsOff ?? false
                save.smbMinutes = (target.smbMinutes ?? settingsManager.preferences.maxSMBBasalMinutes) as NSDecimalNumber?
                save.uamMinutes = (target.uamMinutes ?? settingsManager.preferences.maxUAMSMBBasalMinutes) as NSDecimalNumber?
                save.target = target.target as NSDecimalNumber?
                save.enabled = enabled
                return save
            }

            coredataContext.performAndWait {
                do {
                    try coredataContext.save()
                } catch {
                    debug(.openAPS, "Error saving context : \(error)")
                }
            }

            processQueue.async {
                self.broadcaster.notify(OverrideObserver.self, on: self.processQueue) {
                    $0.overrideDidUpdate(self.recent(), current: self.current())
                }
            }
        }
        // }
    }

    /// The start date of override data available by recent function
    /// - Returns: the oldest date of data returned
    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    private func fetchNumberOfOverrides(numbers: Int) -> [Override]? {
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = numbers
            do {
                return try self.coredataContext.fetch(requestOverrides)
            } catch {
                debug(.openAPS, "Error fetch context : \(error)")
                return nil
            }
        }
    }

    private func fetchOverrides(interval: Date) -> [Override]? {
        var overrideArray = [Override]()
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate(
                format: "date > %@", interval as NSDate
            )
            do {
                try overrideArray = self.coredataContext.fetch(requestOverrides)
            } catch {
                debug(.openAPS, "Error fetch context : \(error)")
            }
        }
        return overrideArray
    }

    private func fetchOverrideById(id: String) -> Override? {
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            requestOverrides.predicate = NSPredicate(
                format: "id == %@", id
            )
            do {
                return try self.coredataContext.fetch(requestOverrides).first
            } catch {
                debug(.openAPS, "Error fetch context : \(error)")
                return nil
            }
        }
    }

    /// Provides the last 24 hours override stored in the core data
    /// - Returns: a array of override profil sorted by date
    func recent() -> [OverrideProfile?] {
        if let overrideRecent = fetchOverrides(interval: syncDate()) {
            return overrideRecent.compactMap {
                OverrideToOverrideProfile($0)
            }
        } else {
            return []
        }
    }

    /// Provides the current override or nil if no is current available
    /// broadcast a observer overrideDidUpdate if the current override has changed since the last current function call
    /// - Returns: A override profil currently in action
    func current() -> OverrideProfile? {
        var newCurrentOverride: OverrideProfile?

        if let overrideRecent = fetchNumberOfOverrides(numbers: 1), let overrideCurrent = overrideRecent.first {
            if overrideCurrent.indefinite {
                newCurrentOverride = OverrideToOverrideProfile(overrideCurrent)

            } else if
                let duration = overrideCurrent.duration as Decimal?,
                let date = overrideCurrent.date,
                (Date().timeIntervalSinceReferenceDate - date.timeIntervalSinceReferenceDate).minutes < Double(duration),
                date <= Date(),
                duration != 0
            {
                newCurrentOverride = OverrideToOverrideProfile(overrideCurrent)
            } else {
                newCurrentOverride = nil
            }
        } else {
            newCurrentOverride = nil
        }

        lastCurrentOverride = newCurrentOverride

        return newCurrentOverride
    }

    /// Cancel the current override
    /// - Returns: the final duration of the event
    func cancelCurrentOverride() -> Decimal? {
        guard var currentOverride = current() else { return nil }

        currentOverride
            .duration =
            Decimal(
                (Date().timeIntervalSinceReferenceDate - currentOverride.createdAt!.timeIntervalSinceReferenceDate)
                    .minutes
            )
        storeOverride([currentOverride], isPresets: false)

        return currentOverride.duration
    }

    /// Apply a override preset as the current override
    /// - Parameter presetId: the identifier of the preset override
    /// - Returns: the date of the creation/start of the current override event
    func applyOverridePreset(_ presetId: String) -> Date? {
        guard var preset = presets().first(where: { $0.id == presetId }) else { return nil }

        // delete the target preset id to not use as a identifier of the new override
        preset.id = UUID().uuidString
        preset.createdAt = Date()
        storeOverride([preset])
        return preset.createdAt
    }
}

import CoreData
import Foundation

/// The active profile's values are the live settings files.
struct StoredTherapyProfiles: Equatable, Sendable {
    /// Nil until the profiles are first stored; Default is active then.
    var activeProfileName: String?
    var inactiveProfiles: [TrioTherapyProfile]
    /// The live settings when the profiles were stored, kept with the active profile's name.
    var activeProfileValues: TrioTherapyProfile?
    var scheduledSwitches: [ScheduledProfileSwitch] = []
    /// Occurrences of the scheduled switches up to this instant are done with. Kept with the active profile.
    var scheduledSwitchesSettledAt: Date?
}

enum TherapyProfileStorageError: Error, Equatable {
    case duplicateName
    case valueOutOfRange(String)
    case noActiveProfile
}

protocol TherapyProfileStorage {
    func fetchProfiles() async throws -> StoredTherapyProfiles
    /// Replaces every stored profile and scheduled switch in one save. Throws without changing anything when two profiles
    /// have the same name ignoring case, a value is out of range, or there is no active profile for the active values, the
    /// scheduled switches or the settled instant.
    func storeProfiles(_ profiles: StoredTherapyProfiles) async throws
    /// Stores only the settled instant of the scheduled switches. Throws `noActiveProfile` before the profiles are stored.
    func settleScheduledSwitches(at date: Date) async throws
}

final class BaseTherapyProfileStorage: TherapyProfileStorage {
    /// One context for all operations, so each replace of the stored profiles runs in order with every other read and write.
    private let context: NSManagedObjectContext

    init(contextProvider: (() -> NSManagedObjectContext)? = nil) {
        context = contextProvider?() ?? CoreDataStack.shared.newTaskContext()
        context.name = "therapyProfileStorage"
    }

    func fetchProfiles() async throws -> StoredTherapyProfiles {
        try await context.perform { [context] in
            let rows = try context.fetch(TherapyProfileStored.fetchRequest())
            let activeRow = rows.first(where: \.isActive)
            return StoredTherapyProfiles(
                activeProfileName: activeRow?.name,
                inactiveProfiles: rows.filter { !$0.isActive }.compactMap(\.therapyProfile),
                activeProfileValues: (activeRow?.entries?.count ?? 0) > 0 ? activeRow?.therapyProfile : nil,
                scheduledSwitches: try context.fetch(ScheduledProfileSwitchStored.fetchRequest())
                    .compactMap(\.scheduledProfileSwitch).sortedByWeek,
                scheduledSwitchesSettledAt: activeRow?.scheduledSwitchesSettledAt
            )
        }
    }

    func storeProfiles(_ profiles: StoredTherapyProfiles) async throws {
        do {
            try Self.validate(profiles)
        } catch {
            warning(.storage, "Therapy profiles not saved", error: error)
            throw error
        }
        try await context.perform { [context] in
            do {
                for row in try context.fetch(TherapyProfileStored.fetchRequest()) {
                    context.delete(row)
                }
                for row in try context.fetch(ScheduledProfileSwitchStored.fetchRequest()) {
                    context.delete(row)
                }
                if let activeProfileName = profiles.activeProfileName {
                    let row = profiles.activeProfileValues.map {
                        TherapyProfileStored.insert($0.renamed(activeProfileName), into: context)
                    } ?? TherapyProfileStored(context: context)
                    row.name = activeProfileName
                    row.isActive = true
                    row.scheduledSwitchesSettledAt = profiles.scheduledSwitchesSettledAt
                }
                for profile in profiles.inactiveProfiles {
                    TherapyProfileStored.insert(profile, into: context)
                }
                for entry in profiles.scheduledSwitches {
                    ScheduledProfileSwitchStored.insert(entry, into: context)
                }
                try context.save()
            } catch {
                context.rollback()
                warning(.storage, "Saving therapy profiles failed", error: error)
                throw error
            }
        }
    }

    func settleScheduledSwitches(at date: Date) async throws {
        try await context.perform { [context] in
            do {
                let request = TherapyProfileStored.fetchRequest()
                request.predicate = NSPredicate(format: "isActive == %@", true as NSNumber)
                let rows = try context.fetch(request)
                guard !rows.isEmpty else { throw TherapyProfileStorageError.noActiveProfile }
                rows.forEach { $0.scheduledSwitchesSettledAt = date }
                try context.save()
            } catch {
                context.rollback()
                warning(.storage, "Saving the settled instant of the scheduled profile switches failed", error: error)
                throw error
            }
        }
    }

    private static func validate(_ profiles: StoredTherapyProfiles) throws {
        let hasActiveProfileState = profiles.activeProfileValues != nil || !profiles.scheduledSwitches.isEmpty ||
            profiles.scheduledSwitchesSettledAt != nil
        if profiles.activeProfileName == nil, hasActiveProfileState {
            throw TherapyProfileStorageError.noActiveProfile
        }

        var names = Set<String>()
        for name in profiles.inactiveProfiles.map(\.name) + [profiles.activeProfileName].compactMap({ $0 }) {
            guard names.insert(name.folding(options: .caseInsensitive, locale: nil)).inserted else {
                throw TherapyProfileStorageError.duplicateName
            }
        }

        let day = 0 ..< 24 * 3600
        for profile in profiles.inactiveProfiles + [profiles.activeProfileValues].compactMap({ $0 }) {
            let offsets = (profile.basal + profile.carbRatio + profile.sensitivity).map(\.seconds) + profile.target.map(\.seconds)
            if let offset = offsets.first(where: { !day.contains($0) }) {
                throw TherapyProfileStorageError.valueOutOfRange("schedule offset \(offset)")
            }
        }
        for entry in profiles.scheduledSwitches {
            guard (1 ... 7).contains(entry.weekday) else {
                throw TherapyProfileStorageError.valueOutOfRange("weekday \(entry.weekday)")
            }
            guard day.contains(entry.time), entry.time % 60 == 0 else {
                throw TherapyProfileStorageError.valueOutOfRange("time \(entry.time)")
            }
        }
    }
}

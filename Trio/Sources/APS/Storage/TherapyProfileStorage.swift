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

protocol TherapyProfileStorage {
    func fetchProfiles() throws -> StoredTherapyProfiles
    /// Replaces every stored profile and scheduled switch in one save.
    func storeProfiles(_ profiles: StoredTherapyProfiles) async throws
    /// Stores only the settled instant of the scheduled switches.
    func settleScheduledSwitches(at date: Date) async throws
}

final class BaseTherapyProfileStorage: TherapyProfileStorage {
    private let context: NSManagedObjectContext

    init(contextProvider: (() -> NSManagedObjectContext)? = nil) {
        context = contextProvider?() ?? CoreDataStack.shared.newTaskContext()
        context.name = "therapyProfileStorage"
    }

    func fetchProfiles() throws -> StoredTherapyProfiles {
        try context.performAndWait {
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
            let request = TherapyProfileStored.fetchRequest()
            request.predicate = NSPredicate(format: "isActive == %@", true as NSNumber)
            try context.fetch(request).forEach { $0.scheduledSwitchesSettledAt = date }
            try context.save()
        }
    }
}

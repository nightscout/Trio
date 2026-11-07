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

/// A switch to another profile, kept until it is uploaded to Nightscout.
struct TherapyProfileSwitch: Equatable, Sendable {
    enum Trigger: String, Sendable {
        case local
        case remote
        case scheduled
    }

    let name: String
    let date: Date
    var trigger: Trigger?
}

extension TherapyProfileSwitch.Trigger {
    /// The `notes` of the Profile Switch treatment; a local switch has none.
    var nightscoutNote: String? {
        switch self {
        case .local: return nil
        case .remote: return "Remote"
        case .scheduled: return "Scheduled"
        }
    }
}

protocol TherapyProfileStorage {
    func fetchProfiles() throws -> StoredTherapyProfiles
    /// Replaces every stored profile and scheduled switch in one save. With `switchDate`, the same save records that
    /// `profiles.activeProfileName` became active then.
    func storeProfiles(
        _ profiles: StoredTherapyProfiles,
        switchDate: Date?,
        switchTrigger: TherapyProfileSwitch.Trigger?
    ) async throws
    /// Stores only the settled instant of the scheduled switches.
    func settleScheduledSwitches(at date: Date) async throws
    /// True when the stored profiles or scheduled switches changed after they were last uploaded to Nightscout.
    func profilesNotYetUploaded() throws -> Bool
    /// Marks the stored profiles and scheduled switches uploaded, unless they changed from `profiles` since.
    func markProfilesUploaded(_ profiles: StoredTherapyProfiles) async throws
    /// Profile switches not yet uploaded to Nightscout, oldest first.
    func profileSwitchesNotYetUploaded() throws -> [TherapyProfileSwitch]
    func markSwitchUploaded(_ profileSwitch: TherapyProfileSwitch) async throws
}

extension TherapyProfileStorage {
    func storeProfiles(_ profiles: StoredTherapyProfiles) async throws {
        try await storeProfiles(profiles, switchDate: nil, switchTrigger: nil)
    }
}

final class BaseTherapyProfileStorage: TherapyProfileStorage {
    private let context: NSManagedObjectContext

    init(contextProvider: (() -> NSManagedObjectContext)? = nil) {
        context = contextProvider?() ?? CoreDataStack.shared.newTaskContext()
        context.name = "therapyProfileStorage"
    }

    func fetchProfiles() throws -> StoredTherapyProfiles {
        try context.performAndWait {
            Self.profiles(
                in: try context.fetch(TherapyProfileStored.fetchRequest()),
                switches: try context.fetch(ScheduledProfileSwitchStored.fetchRequest())
            )
        }
    }

    private static func profiles(
        in rows: [TherapyProfileStored],
        switches: [ScheduledProfileSwitchStored]
    ) -> StoredTherapyProfiles {
        let activeRow = rows.first(where: \.isActive)
        return StoredTherapyProfiles(
            activeProfileName: activeRow?.name,
            inactiveProfiles: rows.filter { !$0.isActive }.compactMap(\.therapyProfile).sorted { $0.name < $1.name },
            activeProfileValues: (activeRow?.entries?.count ?? 0) > 0 ? activeRow?.therapyProfile : nil,
            scheduledSwitches: switches.compactMap(\.scheduledProfileSwitch).sortedByWeek,
            scheduledSwitchesSettledAt: activeRow?.scheduledSwitchesSettledAt
        )
    }

    func storeProfiles(
        _ profiles: StoredTherapyProfiles,
        switchDate: Date?,
        switchTrigger: TherapyProfileSwitch.Trigger?
    ) async throws {
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
                    if let switchDate {
                        let profileSwitch = TherapyProfileSwitchStored(context: context)
                        profileSwitch.name = activeProfileName
                        profileSwitch.date = switchDate
                        profileSwitch.trigger = switchTrigger?.rawValue
                    }
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

    func profilesNotYetUploaded() throws -> Bool {
        try context.performAndWait {
            let predicate = NSPredicate(format: "isUploadedToNS == %@", false as NSNumber)
            let profiles = TherapyProfileStored.fetchRequest()
            profiles.predicate = predicate
            let switches = ScheduledProfileSwitchStored.fetchRequest()
            switches.predicate = predicate
            return try context.count(for: profiles) > 0 || context.count(for: switches) > 0
        }
    }

    /// The settled instant is not part of the profile document, so it is not compared.
    func markProfilesUploaded(_ profiles: StoredTherapyProfiles) async throws {
        try await context.perform { [context] in
            let rows = try context.fetch(TherapyProfileStored.fetchRequest())
            let switches = try context.fetch(ScheduledProfileSwitchStored.fetchRequest())
            var uploaded = profiles
            uploaded.inactiveProfiles.sort { $0.name < $1.name }
            uploaded.scheduledSwitches = uploaded.scheduledSwitches.sortedByWeek
            var current = Self.profiles(in: rows, switches: switches)
            current.scheduledSwitchesSettledAt = uploaded.scheduledSwitchesSettledAt
            guard current == uploaded else { return }
            rows.forEach { $0.isUploadedToNS = true }
            switches.forEach { $0.isUploadedToNS = true }
            try context.save()
        }
    }

    func profileSwitchesNotYetUploaded() throws -> [TherapyProfileSwitch] {
        try context.performAndWait {
            let request = TherapyProfileSwitchStored.fetchRequest()
            request.predicate = NSPredicate(format: "isUploadedToNS == %@", false as NSNumber)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \TherapyProfileSwitchStored.date, ascending: true)]
            return try context.fetch(request).compactMap { row in
                guard let name = row.name, let date = row.date else { return nil }
                return TherapyProfileSwitch(
                    name: name,
                    date: date,
                    trigger: row.trigger.flatMap(TherapyProfileSwitch.Trigger.init)
                )
            }
        }
    }

    func markSwitchUploaded(_ profileSwitch: TherapyProfileSwitch) async throws {
        try await context.perform { [context] in
            let request = TherapyProfileSwitchStored.fetchRequest()
            request.predicate = NSPredicate(
                format: "name == %@ AND date == %@",
                profileSwitch.name,
                profileSwitch.date as NSDate
            )
            try context.fetch(request).forEach { $0.isUploadedToNS = true }
            try context.save()
        }
    }
}

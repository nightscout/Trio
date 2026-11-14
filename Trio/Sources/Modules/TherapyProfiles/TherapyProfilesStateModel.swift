import Observation
import SwiftUI

extension TherapyProfiles {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() private var therapyProfileManager: TherapyProfileManager!
        @ObservationIgnored @Injected() private var broadcaster: Broadcaster!

        var profiles: [TrioTherapyProfile] = []
        var activeProfileName = TrioTherapyProfile.defaultName
        var scheduledSwitches: [ScheduledProfileSwitch] = []
        var units: GlucoseUnits = .mgdL
        var isBusy = false
        var errorMessage: String?

        override func subscribe() {
            units = settingsManager.settings.units
            reload()
            broadcaster.register(TherapyProfilesObserver.self, observer: self)
        }

        func reload() {
            profiles = therapyProfileManager.profiles()
            activeProfileName = therapyProfileManager.activeProfileName
            scheduledSwitches = therapyProfileManager.scheduledSwitches()
        }

        func profile(named name: String) -> TrioTherapyProfile? {
            profiles.first { $0.name == name }
        }

        func isActive(_ profile: TrioTherapyProfile) -> Bool {
            profile.name == activeProfileName
        }

        /// The reason `name` cannot be used, or nil. `renaming` is the name of the profile being renamed.
        func nameProblem(_ name: String, renaming: String? = nil) -> String? {
            TherapyProfileValidator.validateName(
                name.trimmingCharacters(in: .whitespacesAndNewlines),
                existingNames: profiles.map(\.name).filter { $0 != renaming }
            )
        }

        func saveActiveProfileAsNew(named name: String) {
            let active = therapyProfileManager.activeProfile()
            perform {
                try await self.therapyProfileManager.save(
                    active.renamed(name.trimmingCharacters(in: .whitespacesAndNewlines)),
                    originalName: nil,
                    baseFingerprint: nil
                )
            }
        }

        func activate(_ name: String) {
            guard let profile = profile(named: name) else { return }
            perform {
                try await self.therapyProfileManager.activate(name, expectedFingerprint: profile.fingerprint(units: .mgdL))
            }
        }

        func rename(_ name: String, to newName: String, completion: @escaping (Bool) -> Void) {
            guard let profile = profile(named: name) else { return }
            perform(completion: completion) {
                try await self.therapyProfileManager.save(
                    profile.renamed(newName.trimmingCharacters(in: .whitespacesAndNewlines)),
                    originalName: name,
                    baseFingerprint: profile.fingerprint(units: .mgdL)
                )
            }
        }

        func delete(_ name: String, completion: @escaping (Bool) -> Void) {
            guard let profile = profile(named: name) else { return }
            perform(completion: completion) {
                try await self.therapyProfileManager.delete(name, expectedFingerprint: profile.fingerprint(units: .mgdL))
            }
        }

        // MARK: Scheduled switches

        func scheduledSwitchCount(for profileName: String) -> Int {
            scheduledSwitches.filter { $0.profileName == profileName }.count
        }

        /// The reason `entry` cannot be saved, or nil.
        func scheduledSwitchProblem(_ entry: ScheduledProfileSwitch) -> String? {
            if let taken = scheduledSwitches.first(where: {
                $0.id != entry.id && $0.weekday == entry.weekday && $0.time == entry.time
            }) {
                return String(localized: "\(taken.profileName) already starts \(Self.startText(taken)).")
            }
            if !scheduledSwitches.contains(where: { $0.id == entry.id }),
               scheduledSwitches.count >= ScheduledProfileSwitch.maxCount
            {
                return String(localized: "There can be at most \(ScheduledProfileSwitch.maxCount) scheduled switches.")
            }
            return nil
        }

        func saveScheduledSwitch(_ entry: ScheduledProfileSwitch, completion: @escaping (Bool) -> Void = { _ in }) {
            var entries = scheduledSwitches
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = entry
            } else {
                entries.append(entry)
            }
            saveScheduledSwitches(entries, completion: completion)
        }

        func deleteScheduledSwitch(_ id: String, completion: @escaping (Bool) -> Void = { _ in }) {
            saveScheduledSwitches(scheduledSwitches.filter { $0.id != id }, completion: completion)
        }

        func setPaused(_ paused: Bool, for id: String) {
            guard var entry = scheduledSwitches.first(where: { $0.id == id }) else { return }
            entry.paused = paused
            saveScheduledSwitch(entry)
        }

        private func saveScheduledSwitches(_ entries: [ScheduledProfileSwitch], completion: @escaping (Bool) -> Void) {
            let base = scheduledSwitches.fingerprint
            perform(completion: completion) {
                try await self.therapyProfileManager.saveScheduledSwitches(entries, baseFingerprint: base)
            }
        }

        /// "Saturday 13:00"
        static func startText(_ entry: ScheduledProfileSwitch) -> String {
            "\(TherapyProfileValidator.weekdayName(entry.weekday)) \(TherapyProfileValidator.timeString(entry.time))"
        }

        /// "Sat 13:00"
        static func shortStartText(_ entry: ScheduledProfileSwitch) -> String {
            let symbols = Calendar.current.shortWeekdaySymbols
            let day = symbols.indices.contains(entry.weekday - 1) ? symbols[entry.weekday - 1] : String(entry.weekday)
            return "\(day) \(TherapyProfileValidator.timeString(entry.time))"
        }

        /// The next unpaused start after this entry's next start, when it is another start.
        func nextStart(after entry: ScheduledProfileSwitch, now: Date = Date()) -> ScheduledProfileSwitch? {
            guard !entry.paused, let start = entry.occurrence(after: now, calendar: .current),
                  let next = scheduledSwitches.nextOccurrence(after: start, calendar: .current),
                  next.entry.id != entry.id
            else { return nil }
            return next.entry
        }

        func nextStart(now: Date = Date()) -> ScheduledProfileSwitch? {
            scheduledSwitches.nextOccurrence(after: now, calendar: .current)?.entry
        }

        private func perform<T>(
            completion: @escaping (Bool) -> Void = { _ in },
            _ operation: @escaping () async throws -> T
        ) {
            isBusy = true
            Task { @MainActor in
                do {
                    _ = try await operation()
                    completion(true)
                } catch {
                    errorMessage = error.localizedDescription
                    completion(false)
                }
                reload()
                isBusy = false
            }
        }
    }
}

extension TherapyProfiles.StateModel: TherapyProfilesObserver {
    func therapyProfilesDidChange() {
        reload()
    }
}

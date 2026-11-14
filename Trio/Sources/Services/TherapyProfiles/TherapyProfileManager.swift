import Foundation
import LoopKit
import Swinject

enum TherapyProfileError: Error, LocalizedError, Equatable {
    case notFound(String)
    case alreadyExists(String)
    case tooManyProfiles
    case invalidName(String)
    case invalidValues(String)
    case conflict(String)
    case cannotDeleteActive
    case cannotDeleteDefault
    case cannotRenameDefault
    case noPump
    case pumpSyncFailed(String)
    case pumpSuspended
    case pumpRestoreFailed(pumpProfile: String, liveProfile: String)
    case storageFailed
    case liveSettingsNotStored
    case activeProfileChanged(expected: String, current: String)
    case scheduledSwitchesConflict
    case invalidScheduledSwitches(String)

    var errorDescription: String? {
        switch self {
        case let .notFound(name):
            return String(localized: "There is no profile named \(name).")
        case let .alreadyExists(name):
            return String(localized: "A profile named \(name) already exists.")
        case .tooManyProfiles:
            return String(
                localized: "There can be at most \(TherapyProfileLimits.maxProfiles) profiles. Delete a profile before creating another."
            )
        case let .invalidName(reason),
             let .invalidValues(reason):
            return reason
        case let .conflict(name):
            return String(localized: "Profile \(name) has changed since it was loaded. Reload and try again.")
        case .cannotDeleteActive:
            return String(localized: "The active profile cannot be deleted.")
        case .cannotDeleteDefault:
            return String(localized: "The Default profile cannot be deleted.")
        case .cannotRenameDefault:
            return String(localized: "The Default profile cannot be renamed.")
        case .noPump:
            return String(localized: "No pump is connected, so the basal rates cannot be sent to the pump.")
        case let .pumpSyncFailed(reason):
            return String(localized: "The pump did not accept the basal rates: \(reason)")
        case .pumpSuspended:
            return String(localized: "Insulin delivery is suspended. Resume delivery before changing the basal rates.")
        case let .pumpRestoreFailed(pumpProfile, liveProfile):
            return String(
                localized: "The profiles could not be saved, and the pump may still hold the basal rates of profile \(pumpProfile) while Trio uses those of profile \(liveProfile). Check the basal schedule on the pump."
            )
        case .storageFailed:
            return String(localized: "The profiles could not be saved.")
        case .liveSettingsNotStored:
            return String(
                localized: "Trio uses the new settings, but could not store them with the active profile. Save again to retry."
            )
        case let .activeProfileChanged(expected, current) where expected == current:
            return String(
                localized: "Profile \(current) was changed while you were editing, so your changes were not saved. Open this screen again to edit the current values."
            )
        case let .activeProfileChanged(_, current):
            return String(
                localized: "Profile \(current) became active while you were editing, so your changes were not saved. Open this screen again to edit the current values."
            )
        case .scheduledSwitchesConflict:
            return String(localized: "The scheduled switches have changed since they were loaded. Reload and try again.")
        case let .invalidScheduledSwitches(reason):
            return reason
        }
    }
}

protocol TherapyProfilesObserver {
    func therapyProfilesDidChange()
}

/// Named therapy profiles. The active profile's values are the live settings files oref reads; the others are stored in
/// Core Data. Every change runs one at a time, in the order the calls arrive.
protocol TherapyProfileManager: AnyObject {
    var activeProfileName: String { get }
    func activeProfile() -> TrioTherapyProfile
    /// Default first, then by name.
    func profiles() -> [TrioTherapyProfile]
    /// `default` also names the Default profile.
    func profile(named name: String) -> TrioTherapyProfile?

    /// Validates, writes the basal schedule to the pump, then makes the profile's values the live settings.
    @discardableResult func activate(_ name: String, expectedFingerprint: String?) async throws -> TrioTherapyProfile
    /// Creates the profile when `originalName` is nil, otherwise updates or renames that profile. Saving the active
    /// profile writes a changed basal schedule to the pump and changes the live settings.
    @discardableResult func save(
        _ profile: TrioTherapyProfile,
        originalName: String?,
        baseFingerprint: String?
    ) async throws -> TrioTherapyProfile
    /// Also removes the scheduled switches to the profile and returns how many there were.
    @discardableResult func delete(_ name: String, expectedFingerprint: String?) async throws -> Int
    /// Runs `write`, a therapy editor's save of the live settings, in turn with the other changes. Throws
    /// `activeProfileChanged` without running `write` when another profile is active or the active profile's values no
    /// longer match `expectedFingerprint`, and `pumpSuspended` when `write` sends the basal schedule to a suspended pump.
    /// Throws `liveSettingsNotStored` when `write` succeeded but storing the active profile's values failed.
    @discardableResult func saveLiveSettings(
        expectedActiveName: String,
        expectedFingerprint: String,
        writesBasalSchedule: Bool,
        write: @escaping @Sendable() async throws -> Void
    ) async throws -> TrioTherapyProfile
    /// Makes the profile whose values the live settings hold active, when the app stopped during a switch after writing
    /// the live settings and before storing the profiles.
    func completeInterruptedSwitch() async

    /// Ordered as a week from Monday.
    func scheduledSwitches() -> [ScheduledProfileSwitch]
    /// Replaces the scheduled switches. Only starts after now run. Throws `scheduledSwitchesConflict` when the current
    /// list no longer matches `baseFingerprint`.
    @discardableResult func saveScheduledSwitches(
        _ entries: [ScheduledProfileSwitch],
        baseFingerprint: String?
    ) async throws -> [ScheduledProfileSwitch]
    /// Switches to the profile of the newest scheduled start that is due, and arms the alert for a start that does not
    /// happen in time.
    func runDueScheduledSwitch() async
}

extension TherapyProfileManager {
    @discardableResult func saveLiveSettings(
        expectedActiveName: String,
        expectedFingerprint: String,
        write: @escaping @Sendable() async throws -> Void
    ) async throws -> TrioTherapyProfile {
        try await saveLiveSettings(
            expectedActiveName: expectedActiveName,
            expectedFingerprint: expectedFingerprint,
            writesBasalSchedule: false,
            write: write
        )
    }
}

final class BaseTherapyProfileManager: TherapyProfileManager, Injectable, @unchecked Sendable {
    @Injected() private var therapyProfileStorage: TherapyProfileStorage!
    @Injected() private var fileStorage: FileStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var nightscoutManager: NightscoutManager!
    @Injected() private var tidepoolManager: TidepoolManager!
    @Injected() private var apsManager: APSManager!
    @Injected() private var trioAlertManager: TrioAlertManager!

    private let serializer = TherapyProfileSerializer()
    private let syncBasalScheduleOverride: (@Sendable([BasalProfileEntry]) async throws -> Void)?
    private let basalLimitsOverride: (@Sendable() -> TherapyBasalLimits)?
    private let pumpSuspendedOverride: (@Sendable() -> Bool)?
    private let bolusInProgressOverride: (@Sendable() -> Bool)?
    private let recompute: (@Sendable() async -> Void)?
    private let now: @Sendable() -> Date
    private let calendarOverride: Calendar?
    private let armedAlertLock = NSLock()
    private var armedAlert: ArmedScheduledSwitchAlert?

    /// Tests pass `syncBasalSchedule`, `basalLimits`, `pumpSuspended`, `bolusInProgress` and `recompute` in place of the
    /// pump and the determination.
    init(
        resolver: Resolver,
        syncBasalSchedule: (@Sendable([BasalProfileEntry]) async throws -> Void)? = nil,
        basalLimits: (@Sendable() -> TherapyBasalLimits)? = nil,
        pumpSuspended: (@Sendable() -> Bool)? = nil,
        bolusInProgress: (@Sendable() -> Bool)? = nil,
        recompute: (@Sendable() async -> Void)? = nil,
        now: @escaping @Sendable() -> Date = { Date() },
        calendar: Calendar? = nil
    ) {
        syncBasalScheduleOverride = syncBasalSchedule
        basalLimitsOverride = basalLimits
        pumpSuspendedOverride = pumpSuspended
        bolusInProgressOverride = bolusInProgress
        self.recompute = recompute
        self.now = now
        calendarOverride = calendar
        injectServices(resolver)
    }

    /// Scheduled switches are wall-clock times in the time zone the profiles are uploaded with.
    private var calendar: Calendar {
        calendarOverride ?? Calendar.current
    }

    private var basalLimits: TherapyBasalLimits {
        if let basalLimitsOverride { return basalLimitsOverride() }
        let rates = deviceDataManager.pumpManager?.supportedBasalRates
            .filter { $0 > 0 }
            .map { Decimal($0).rounded(scale: 3) }
        return TherapyBasalLimits(
            supportedRates: rates ?? TherapyBasalLimits.fallbackRates,
            maxBasal: settingsManager.pumpSettings.maxBasal
        )
    }

    var activeProfileName: String {
        (try? loadState())?.activeProfileName ?? TrioTherapyProfile.defaultName
    }

    func activeProfile() -> TrioTherapyProfile {
        (try? loadState())?.activeProfile ?? liveProfile(named: TrioTherapyProfile.defaultName)
    }

    func profiles() -> [TrioTherapyProfile] {
        (try? loadState())?.profiles ?? [liveProfile(named: TrioTherapyProfile.defaultName)]
    }

    func profile(named name: String) -> TrioTherapyProfile? {
        (try? loadState())?.profile(named: name)
    }

    // MARK: State

    private struct State {
        var activeProfileName: String
        /// The active profile carries the live settings.
        var profiles: [TrioTherapyProfile]
        var scheduledSwitches: [ScheduledProfileSwitch]
        var scheduledSwitchesSettledAt: Date?

        var activeProfile: TrioTherapyProfile? { profile(named: activeProfileName) }

        func profile(named name: String) -> TrioTherapyProfile? {
            if name == TrioTherapyProfile.defaultStoreKey {
                return profiles.first(where: \.isDefault)
            }
            return profiles.first { $0.name == name }
        }

        var stored: StoredTherapyProfiles {
            StoredTherapyProfiles(
                activeProfileName: activeProfileName,
                inactiveProfiles: profiles.filter { $0.name != activeProfileName },
                activeProfileValues: activeProfile,
                scheduledSwitches: scheduledSwitches,
                scheduledSwitchesSettledAt: scheduledSwitchesSettledAt
            )
        }
    }

    /// When the live settings differ from the values stored with the active profile and equal another stored profile's,
    /// a switch wrote the live settings and stopped before storing the profiles: that profile is active, and the stored
    /// values belong to the previously active one.
    private func loadState() throws -> State {
        let stored = try therapyProfileStorage.fetchProfiles()
        var activeName = stored.activeProfileName ?? TrioTherapyProfile.defaultName
        var inactiveProfiles = stored.inactiveProfiles
        let live = liveProfile(named: activeName)
        if let storedValues = stored.activeProfileValues, !storedValues.hasSameValues(as: live),
           let index = inactiveProfiles.firstIndex(where: { $0.hasSameValues(as: live) })
        {
            let switchedTo = inactiveProfiles.remove(at: index)
            inactiveProfiles.append(storedValues.renamed(activeName))
            activeName = switchedTo.name
        }
        let profiles = (inactiveProfiles + [live.renamed(activeName)]).sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return State(
            activeProfileName: activeName,
            profiles: profiles,
            scheduledSwitches: stored.scheduledSwitches,
            scheduledSwitchesSettledAt: stored.scheduledSwitchesSettledAt
        )
    }

    private func liveProfile(named name: String) -> TrioTherapyProfile {
        let basal = fileStorage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
            ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
            ?? []
        let carbRatios = fileStorage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
            ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
            ?? CarbRatios(units: .grams, schedule: [])
        let sensitivities = fileStorage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
            ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
            ?? InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])
        let targets = fileStorage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
            ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        return TrioTherapyProfile(
            name: name,
            basalProfile: basal,
            carbRatios: carbRatios,
            insulinSensitivities: sensitivities,
            bgTargets: targets
        )
    }

    /// Writes the live settings files and checks that they read back as written.
    private func writeLive(_ profile: TrioTherapyProfile) throws {
        fileStorage.save(profile.basalProfileEntries, as: OpenAPS.Settings.basalProfile)
        fileStorage.save(profile.carbRatios, as: OpenAPS.Settings.carbRatios)
        fileStorage.save(profile.insulinSensitivities, as: OpenAPS.Settings.insulinSensitivities)
        fileStorage.save(profile.bgTargets, as: OpenAPS.Settings.bgTargets)
        guard liveProfile(named: profile.name).hasSameValues(as: profile) else {
            warning(.settings, "Live therapy settings did not read back as written")
            throw TherapyProfileError.storageFailed
        }
    }

    /// Writes the live settings, then the stored profiles. A failure restores the previous live settings and basal schedule.
    private func commit(_ state: State, live: TrioTherapyProfile, previousLive: TrioTherapyProfile) async throws {
        do {
            try writeLive(live)
            try await therapyProfileStorage.storeProfiles(state.stored)
        } catch let commitError {
            try? writeLive(previousLive)
            if live.basal != previousLive.basal {
                do {
                    try await syncBasalSchedule(previousLive.basalProfileEntries)
                } catch let restoreError {
                    error(
                        .settings,
                        "Restoring the basal schedule of profile \(previousLive.fingerprint(units: .mgdL)) on the pump failed",
                        error: restoreError
                    )
                    throw TherapyProfileError.pumpRestoreFailed(pumpProfile: live.name, liveProfile: previousLive.name)
                }
            }
            throw commitError as? TherapyProfileError ?? .storageFailed
        }
    }

    // MARK: Operations

    @discardableResult func saveLiveSettings(
        expectedActiveName: String,
        expectedFingerprint: String,
        writesBasalSchedule: Bool,
        write: @escaping @Sendable() async throws -> Void
    ) async throws -> TrioTherapyProfile {
        let (saved, stored) = try await serializer.run { () -> (TrioTherapyProfile, Bool) in
            var state = try self.loadState()
            guard let active = state.activeProfile else { throw TherapyProfileError.storageFailed }
            guard active.name == expectedActiveName, active.matchesFingerprint(expectedFingerprint) else {
                warning(.settings, "Therapy settings edit refused, the active profile changed while editing")
                throw TherapyProfileError.activeProfileChanged(expected: expectedActiveName, current: active.name)
            }
            if writesBasalSchedule, self.isPumpSuspended {
                warning(.settings, "Basal schedule not sent, the pump is suspended")
                throw TherapyProfileError.pumpSuspended
            }
            try await write()
            let live = self.liveProfile(named: active.name)
            if let index = state.profiles.firstIndex(where: { $0.name == active.name }) {
                state.profiles[index] = live
            }
            do {
                try await self.therapyProfileStorage.storeProfiles(state.stored)
                return (live, true)
            } catch {
                warning(.settings, "Storing the therapy profiles after a therapy settings edit failed", error: error)
                return (live, false)
            }
        }
        await didChange(liveSettings: saved, refreshDetermination: false)
        guard stored else { throw TherapyProfileError.liveSettingsNotStored }
        return saved
    }

    func completeInterruptedSwitch() async {
        do {
            let switchedTo = try await serializer.run { () -> String? in
                var state = try self.loadState()
                let storedActiveName = try self.therapyProfileStorage.fetchProfiles().activeProfileName
                guard let storedActiveName, storedActiveName != state.activeProfileName else { return nil }
                state.scheduledSwitchesSettledAt = self.now()
                try await self.therapyProfileStorage.storeProfiles(state.stored)
                return state.activeProfileName
            }
            guard let switchedTo else { return }
            warning(.settings, "A switch to therapy profile \(switchedTo) was interrupted and is now completed")
            await didChange(liveSettings: nil)
        } catch {
            warning(.settings, "Checking for an interrupted therapy profile switch failed", error: error)
        }
    }

    @discardableResult func activate(_ name: String, expectedFingerprint: String?) async throws -> TrioTherapyProfile {
        let (profile, switched) = try await serializer.run { () -> (TrioTherapyProfile, Bool) in
            var state = try self.loadState()
            guard let target = state.profile(named: name) else { throw TherapyProfileError.notFound(name) }
            if let expectedFingerprint, !target.matchesFingerprint(expectedFingerprint) {
                throw TherapyProfileError.conflict(target.name)
            }
            guard target.name != state.activeProfileName else { return (target, false) }
            if let reason = TherapyProfileValidator.validate(target, basalLimits: self.basalLimits) {
                throw TherapyProfileError.invalidValues(reason)
            }

            let previousLive = self.liveProfile(named: state.activeProfileName)
            try await self.syncPump(target)
            state.activeProfileName = target.name
            state.scheduledSwitchesSettledAt = self.now()
            try await self.commit(state, live: target, previousLive: previousLive)
            return (target, true)
        }
        if switched {
            info(.settings, "Therapy profile \(profile.name) is active")
            await didChange(liveSettings: profile)
        }
        return profile
    }

    @discardableResult func save(
        _ profile: TrioTherapyProfile,
        originalName: String?,
        baseFingerprint: String?
    ) async throws -> TrioTherapyProfile {
        let (saved, liveChanged, changed) = try await serializer.run { () -> (TrioTherapyProfile, Bool, Bool) in
            var state = try self.loadState()

            var original: TrioTherapyProfile?
            if let originalName {
                guard let found = state.profile(named: originalName) else { throw TherapyProfileError.notFound(originalName) }
                if let baseFingerprint, !found.matchesFingerprint(baseFingerprint) {
                    throw TherapyProfileError.conflict(found.name)
                }
                original = found
            }

            var newName = profile.name
            if let original, original.isDefault {
                guard newName == original.name || newName == TrioTherapyProfile.defaultStoreKey else {
                    throw TherapyProfileError.cannotRenameDefault
                }
                newName = original.name
            } else {
                if let reason = TherapyProfileValidator.validateName(newName, existingNames: []) {
                    throw TherapyProfileError.invalidName(reason)
                }
                if original == nil, state.profiles.count >= TherapyProfileLimits.maxProfiles {
                    throw TherapyProfileError.tooManyProfiles
                }
                let otherNames = state.profiles.map(\.name).filter { $0 != original?.name }
                if otherNames.contains(where: { $0.caseInsensitiveCompare(newName) == .orderedSame }) {
                    throw TherapyProfileError.alreadyExists(newName)
                }
            }

            let updated = profile.renamed(newName)
            let keepsValues = original.map { updated.hasSameValues(as: $0) } ?? false
            if !keepsValues, let reason = TherapyProfileValidator.validate(updated, basalLimits: self.basalLimits) {
                throw TherapyProfileError.invalidValues(reason)
            }
            if updated == original {
                return (updated, false, false)
            }

            if let original, let index = state.profiles.firstIndex(where: { $0.name == original.name }) {
                state.profiles[index] = updated
                state.scheduledSwitches = state.scheduledSwitches.renamingProfile(original.name, to: updated.name)
            } else {
                state.profiles.append(updated)
            }

            guard let original, original.name == state.activeProfileName else {
                try await self.therapyProfileStorage.storeProfiles(state.stored)
                return (updated, false, true)
            }
            if updated.basal != original.basal {
                try await self.syncPump(updated)
            }
            state.activeProfileName = updated.name
            try await self.commit(state, live: updated, previousLive: original)
            return (updated, !updated.hasSameValues(as: original), true)
        }

        guard changed else { return saved }
        info(.settings, "Therapy profile \(saved.fingerprint(units: .mgdL)) saved")
        await didChange(liveSettings: liveChanged ? saved : nil)
        return saved
    }

    @discardableResult func delete(_ name: String, expectedFingerprint: String?) async throws -> Int {
        let (deleted, removedSwitches) = try await serializer.run { () -> (TrioTherapyProfile, Int) in
            var state = try self.loadState()
            guard let target = state.profile(named: name) else { throw TherapyProfileError.notFound(name) }
            if target.isDefault { throw TherapyProfileError.cannotDeleteDefault }
            if target.name == state.activeProfileName { throw TherapyProfileError.cannotDeleteActive }
            if let expectedFingerprint, !target.matchesFingerprint(expectedFingerprint) {
                throw TherapyProfileError.conflict(target.name)
            }
            state.profiles.removeAll { $0.name == target.name }
            let remainingSwitches = state.scheduledSwitches.removingProfile(target.name)
            let removedSwitches = state.scheduledSwitches.count - remainingSwitches.count
            state.scheduledSwitches = remainingSwitches
            try await self.therapyProfileStorage.storeProfiles(state.stored)
            return (target, removedSwitches)
        }
        info(.settings, "Therapy profile \(deleted.fingerprint(units: .mgdL)) deleted with \(removedSwitches) scheduled switches")
        await didChange(liveSettings: nil)
        return removedSwitches
    }

    // MARK: Scheduled switches

    /// A start that is due longer than this is not applied.
    static let scheduledSwitchGrace: TimeInterval = 24 * 3600
    /// The alert for a start that has not happened fires this long after it.
    static let scheduledSwitchAlertDelay: TimeInterval = 30 * 60

    func scheduledSwitches() -> [ScheduledProfileSwitch] {
        (try? loadState())?.scheduledSwitches.sortedByWeek ?? []
    }

    @discardableResult func saveScheduledSwitches(
        _ entries: [ScheduledProfileSwitch],
        baseFingerprint: String?
    ) async throws -> [ScheduledProfileSwitch] {
        let saved = try await serializer.run { () -> [ScheduledProfileSwitch] in
            var state = try self.loadState()
            if let baseFingerprint, !state.scheduledSwitches.matchesFingerprint(baseFingerprint) {
                throw TherapyProfileError.scheduledSwitchesConflict
            }
            if let reason = TherapyProfileValidator.validateScheduledSwitches(entries) {
                throw TherapyProfileError.invalidScheduledSwitches(reason)
            }
            state.scheduledSwitches = try entries.map { entry in
                guard let profile = state.profile(named: entry.profileName) else {
                    throw TherapyProfileError.notFound(entry.profileName)
                }
                var entry = entry
                entry.profileName = profile.name
                return entry
            }.sortedByWeek
            state.scheduledSwitchesSettledAt = self.now()
            try await self.therapyProfileStorage.storeProfiles(state.stored)
            return state.scheduledSwitches
        }
        info(.settings, "\(saved.count) scheduled profile switches saved, \(saved.filter(\.paused).count) paused")
        await didChange(liveSettings: nil)
        return saved
    }

    private enum ScheduledSwitchRun {
        case idle
        case switched(ScheduledProfileSwitchOccurrence, TrioTherapyProfile, at: Date)
        /// Settled without a switch; the user is told why.
        case failed(ScheduledProfileSwitchOccurrence, reason: String)
        /// Not settled; tried again on the next run.
        case retrying(ScheduledProfileSwitchOccurrence, reason: String)
    }

    func runDueScheduledSwitch() async {
        let run: ScheduledSwitchRun
        do {
            run = try await serializer.run { try await self.runDueScheduledSwitchStep() }
        } catch {
            warning(.settings, "Running the scheduled profile switch failed", error: error)
            return
        }
        switch run {
        case .idle:
            await armScheduledSwitchAlert()
        case let .switched(occurrence, profile, switchDate):
            info(.settings, "Scheduled switch to therapy profile \(profile.fingerprint(units: .mgdL)) done")
            issueScheduledSwitchDone(occurrence, profileName: profile.name, at: switchDate)
            await didChange(liveSettings: profile)
        case let .failed(occurrence, reason):
            warning(.settings, "Scheduled profile switch of \(occurrence.date) not done")
            issueScheduledSwitchFailed(occurrence, reason: reason)
            await armScheduledSwitchAlert()
        case let .retrying(occurrence, reason):
            debug(.settings, "Scheduled profile switch of \(occurrence.date) not done yet, retrying on the next run")
            await armScheduledSwitchAlert(reason: reason)
        }
    }

    private func runDueScheduledSwitchStep() async throws -> ScheduledSwitchRun {
        var state = try loadState()
        let now = self.now()
        guard !state.scheduledSwitches.isEmpty else { return .idle }
        guard let settledAt = state.scheduledSwitchesSettledAt else {
            try await therapyProfileStorage.settleScheduledSwitches(at: now)
            return .idle
        }
        guard let due = state.scheduledSwitches.newestOccurrence(after: settledAt, upTo: now, calendar: calendar) else {
            return .idle
        }
        guard now.timeIntervalSince(due.date) <= Self.scheduledSwitchGrace else {
            try await therapyProfileStorage.settleScheduledSwitches(at: now)
            return .failed(due, reason: String(localized: "Trio could not switch within 24 hours of the scheduled time."))
        }
        guard let target = state.profile(named: due.entry.profileName) else {
            try await therapyProfileStorage.settleScheduledSwitches(at: now)
            return .failed(due, reason: TherapyProfileError.notFound(due.entry.profileName).localizedDescription)
        }
        guard target.name != state.activeProfileName else {
            try await therapyProfileStorage.settleScheduledSwitches(at: now)
            return .idle
        }
        guard !isBolusInProgress else {
            return .retrying(due, reason: String(localized: "A bolus was in progress."))
        }
        if let reason = TherapyProfileValidator.validate(target, basalLimits: basalLimits) {
            try await therapyProfileStorage.settleScheduledSwitches(at: now)
            return .failed(due, reason: reason)
        }

        let previousLive = liveProfile(named: state.activeProfileName)
        do {
            try await syncPump(target)
        } catch {
            return .retrying(due, reason: error.localizedDescription)
        }
        state.activeProfileName = target.name
        state.scheduledSwitchesSettledAt = due.date
        do {
            try await commit(state, live: target, previousLive: previousLive)
        } catch {
            try? await therapyProfileStorage.settleScheduledSwitches(at: now)
            return .failed(due, reason: error.localizedDescription)
        }
        return .switched(due, target, at: now)
    }

    private var isBolusInProgress: Bool {
        if let bolusInProgressOverride { return bolusInProgressOverride() }
        return apsManager.bolusProgress.value != nil
    }

    // MARK: Scheduled switch alerts

    private struct ArmedScheduledSwitchAlert: Equatable {
        let entryID: String
        let date: Date
        let reason: String?
    }

    private static func scheduledSwitchAlertID(_ name: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: "trio.therapyProfiles", alertIdentifier: "scheduledSwitch.\(name)")
    }

    private static let pendingAlertID = scheduledSwitchAlertID("pending")
    private static let doneAlertID = scheduledSwitchAlertID("done")
    private static let failedAlertID = scheduledSwitchAlertID("failed")

    private func timeText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone))
    }

    private func issue(
        _ identifier: Alert.Identifier,
        title: String,
        body: String,
        trigger: Alert.Trigger = .immediate,
        level: Alert.InterruptionLevel
    ) {
        let content = Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: String(localized: "OK"))
        trioAlertManager.retractAlert(identifier: identifier)
        trioAlertManager.issueAlert(Alert(
            identifier: identifier,
            foregroundContent: content,
            backgroundContent: content,
            trigger: trigger,
            interruptionLevel: level
        ))
    }

    private func issueScheduledSwitchDone(_ occurrence: ScheduledProfileSwitchOccurrence, profileName: String, at date: Date) {
        let scheduled = timeText(occurrence.date)
        let body = date.timeIntervalSince(occurrence.date) < 5 * 60 ?
            String(localized: "Trio switched to \(profileName) as scheduled (\(scheduled)).") :
            String(localized: "Trio switched to \(profileName), scheduled for \(scheduled), done at \(timeText(date)).")
        issue(Self.doneAlertID, title: String(localized: "Profile Switched"), body: body, level: .active)
    }

    private func issueScheduledSwitchFailed(_ occurrence: ScheduledProfileSwitchOccurrence, reason: String) {
        issue(
            Self.failedAlertID,
            title: String(localized: "Scheduled Switch Not Done"),
            body: String(localized: "The scheduled switch to \(occurrence.entry.profileName) did not happen: \(reason)"),
            level: .timeSensitive
        )
    }

    /// Arms one alert for 30 minutes after the start that is due or comes next, so the user is told when Trio does not run
    /// then. iOS delivers it whether or not Trio is running. A switch, a settled start or a changed list re-arms it; an
    /// alert that was delivered stays until its start is settled.
    private func armScheduledSwitchAlert(reason: String? = nil) async {
        let now = self.now()
        let state = try? loadState()
        if let state, let settledAt = state.scheduledSwitchesSettledAt,
           let unsettled = state.scheduledSwitches.nextOccurrence(after: settledAt, calendar: calendar),
           unsettled.date.addingTimeInterval(Self.scheduledSwitchAlertDelay) <= now
        {
            return
        }
        let pending: ScheduledProfileSwitchOccurrence? = {
            guard let state, let settledAt = state.scheduledSwitchesSettledAt else { return nil }
            if let due = state.scheduledSwitches.newestOccurrence(after: settledAt, upTo: now, calendar: calendar),
               now.timeIntervalSince(due.date) <= Self.scheduledSwitchGrace
            {
                return due
            }
            return state.scheduledSwitches.nextOccurrence(after: max(now, settledAt), calendar: calendar)
        }()
        let armed = pending.map { ArmedScheduledSwitchAlert(entryID: $0.entry.id, date: $0.date, reason: reason) }
        let changed = armedAlertLock.withLock {
            guard armedAlert != armed else { return false }
            armedAlert = armed
            return true
        }
        guard changed else { return }

        guard let pending else {
            trioAlertManager.retractAlert(identifier: Self.pendingAlertID)
            return
        }
        let fireDate = pending.date.addingTimeInterval(Self.scheduledSwitchAlertDelay)
        guard fireDate > now else { return }
        let name = pending.entry.profileName
        let time = timeText(pending.date)
        issue(
            Self.pendingAlertID,
            title: String(localized: "Scheduled Switch Not Done"),
            body: reason.map {
                String(localized: "Trio has not been able to switch to \(name) as scheduled at \(time): \($0) Open Trio.")
            } ?? String(localized: "Trio has not been able to switch to \(name) as scheduled at \(time). Open Trio."),
            trigger: .delayed(interval: fireDate.timeIntervalSince(now)),
            level: .timeSensitive
        )
    }

    // MARK: Pump

    /// A suspended pump would resume delivery when it takes a basal schedule.
    private var isPumpSuspended: Bool {
        if let pumpSuspendedOverride { return pumpSuspendedOverride() }
        switch deviceDataManager.pumpManager?.status.basalDeliveryState {
        case .suspended,
             .suspending:
            return true
        default:
            return false
        }
    }

    private func syncPump(_ profile: TrioTherapyProfile) async throws {
        guard !isPumpSuspended else {
            warning(.settings, "Basal schedule of profile \(profile.fingerprint(units: .mgdL)) not sent, the pump is suspended")
            throw TherapyProfileError.pumpSuspended
        }
        do {
            try await syncBasalSchedule(profile.basalProfileEntries)
        } catch let error as TherapyProfileError {
            throw error
        } catch {
            warning(.settings, "Pump refused the basal schedule of profile \(profile.fingerprint(units: .mgdL))", error: error)
            throw TherapyProfileError.pumpSyncFailed(error.localizedDescription)
        }
    }

    private func syncBasalSchedule(_ entries: [BasalProfileEntry]) async throws {
        if let syncBasalScheduleOverride {
            return try await syncBasalScheduleOverride(entries)
        }
        try await syncPumpBasalSchedule(entries)
    }

    /// Pump managers take commands on the main thread.
    @MainActor private func syncPumpBasalSchedule(_ entries: [BasalProfileEntry]) async throws {
        guard let pump = deviceDataManager.pumpManager else {
            warning(.settings, "Basal schedule not sent, no pump connected")
            throw TherapyProfileError.noPump
        }
        let items = entries.map {
            RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: pump.scheduleValue(for: $0.rate))
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pump.syncBasalRateSchedule(items: items) { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Side effects

    /// Notifies observers. When the live settings changed, also refreshes the determination unless
    /// `refreshDetermination` is false, and uploads the settings.
    private func didChange(liveSettings profile: TrioTherapyProfile?, refreshDetermination: Bool = true) async {
        await MainActor.run {
            if let profile {
                let basal = profile.basalProfileEntries
                let targets = profile.bgTargets
                let carbRatios = profile.carbRatios
                let sensitivities = profile.insulinSensitivities
                broadcaster.notify(BasalProfileObserver.self, on: .main) { $0.basalProfileDidChange(basal) }
                broadcaster.notify(BGTargetsObserver.self, on: .main) { $0.bgTargetsDidChange(targets) }
                broadcaster.notify(CarbRatiosObserver.self, on: .main) { $0.carbRatiosDidChange(carbRatios) }
                broadcaster.notify(InsulinSensitivitiesObserver.self, on: .main) {
                    $0.insulinSensitivitiesDidChange(sensitivities)
                }
            }
            broadcaster.notify(TherapyProfilesObserver.self, on: .main) { $0.therapyProfilesDidChange() }
        }
        if refreshDetermination {
            await armScheduledSwitchAlert()
        }
        guard profile != nil else { return }

        if refreshDetermination {
            if let recompute {
                await recompute()
            } else {
                do {
                    try await apsManager.determineBasalSync()
                } catch {
                    warning(.settings, "Refreshing the determination after a therapy profile change failed", error: error)
                }
            }
        }
        do {
            try await nightscoutManager.uploadProfiles()
        } catch {
            warning(.nightscout, "Uploading profile after a therapy profile change failed", error: error)
        }
        await tidepoolManager.uploadSettings()
    }
}

/// Runs operations one at a time, in the order they arrive. Calling `run` from inside an operation deadlocks.
private actor TherapyProfileSerializer {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable() async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

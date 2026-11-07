import Foundation

struct FetchedNightscoutProfileStore: Decodable {
    let defaultProfile: String
    let units: String?
    let store: [String: FetchedNightscoutProfile]
    /// Names of store entries that could not be read.
    let unreadableProfiles: [String]
    let scheduledSwitches: [ScheduledProfileSwitch]
    let unreadableScheduledSwitches: Int

    private enum CodingKeys: String, CodingKey {
        case defaultProfile
        case units
        case store
        case scheduledSwitches
    }

    /// Decodes any value, so one unreadable array element does not stop the others.
    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    private struct EntryKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue _: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultProfile = try container.decode(String.self, forKey: .defaultProfile)
        units = try? container.decodeIfPresent(String.self, forKey: .units)
        let entries = try container.nestedContainer(keyedBy: EntryKey.self, forKey: .store)
        var store: [String: FetchedNightscoutProfile] = [:]
        var unreadable: [String] = []
        for key in entries.allKeys {
            if let entry = try? entries.decode(FetchedNightscoutProfile.self, forKey: key) {
                store[key.stringValue] = entry
            } else {
                unreadable.append(key.stringValue)
            }
        }
        self.store = store
        unreadableProfiles = unreadable.sorted()
        let switches = (try? container.decodeIfPresent([Lossy<ScheduledProfileSwitch>].self, forKey: .scheduledSwitches)) ?? []
        scheduledSwitches = switches.compactMap(\.value)
        unreadableScheduledSwitches = switches.count - scheduledSwitches.count
    }

    /// The store key of the active profile: `defaultProfile`, or the `default` entry when `defaultProfile` names none.
    var activeStoreKey: String? {
        if store[defaultProfile] != nil { return defaultProfile }
        return store.keys.sorted().first { $0.caseInsensitiveCompare(TrioTherapyProfile.defaultStoreKey) == .orderedSame }
    }
}

struct FetchedNightscoutProfile: JSON {
    let target_low: [NightscoutTimevalue]
    let target_high: [NightscoutTimevalue]
    let sens: [NightscoutTimevalue]
    let basal: [NightscoutTimevalue]
    let carbratio: [NightscoutTimevalue]
    let units: String?
}

/// The profiles of a Nightscout profile document, converted to mg/dL and validated.
struct NightscoutProfileImport: Equatable {
    struct Skipped: Equatable {
        let name: String
        let reason: String
    }

    /// Every valid store entry except the active one, whose values onboarding imports as the therapy settings.
    let profiles: [TrioTherapyProfile]
    /// The scheduled switches to imported profiles, with Trio's profile names.
    let scheduledSwitches: [ScheduledProfileSwitch]
    /// The Trio name of the document's active profile, or Default when that name is not valid in Trio.
    let activeProfileName: String
    let skipped: [Skipped]
    /// Why the active entry, whose values onboarding imports as the therapy settings, can not be used; nil when it can.
    let activeProblem: String?

    /// Onboarding runs before a pump is set up, so basal rates are checked against the basal editor's list.
    init(store document: FetchedNightscoutProfileStore, basalLimits: TherapyBasalLimits = .editorLimits) {
        let activeKey = document.activeStoreKey
        var profiles: [TrioTherapyProfile] = []
        var skipped = document.unreadableProfiles.map {
            Skipped(name: $0, reason: String(localized: "The profile could not be read."))
        }

        func trioName(_ key: String) -> String {
            key.caseInsensitiveCompare(TrioTherapyProfile.defaultStoreKey) == .orderedSame ? TrioTherapyProfile.defaultName : key
        }

        // The active entry first, so it keeps its name when another entry's name differs only in case.
        let keys = [activeKey].compactMap { $0 } + document.store.keys.sorted().filter { $0 != activeKey }
        var takenNames: [String] = []
        var activeName: String?
        var defaultKey: String?
        for key in keys {
            guard let entry = document.store[key] else { continue }
            let name = trioName(key)
            let isDefault = name == TrioTherapyProfile.defaultName
            if let reason = TherapyProfileValidator.validateName(name, existingNames: takenNames, isDefaultProfile: isDefault) {
                skipped.append(Skipped(
                    name: key,
                    reason: key == activeKey ? String(localized: "\(reason) Trio imports its values as the Default profile.") :
                        reason
                ))
                continue
            }
            takenNames.append(name)
            if key == activeKey {
                activeName = name
                continue
            }
            do {
                let profile = try TrioTherapyProfile(name: name, nightscoutProfile: entry, documentUnits: document.units)
                if let reason = TherapyProfileValidator.validate(profile, basalLimits: basalLimits) {
                    skipped.append(Skipped(name: key, reason: reason))
                } else {
                    profiles.append(profile)
                    if isDefault { defaultKey = key }
                }
            } catch {
                skipped.append(Skipped(name: key, reason: error.localizedDescription))
            }
        }

        if let activeKey, activeName == nil, let defaultKey {
            profiles.removeAll(where: \.isDefault)
            skipped.append(Skipped(
                name: defaultKey,
                reason: String(localized: "The Default profile takes the values of the active profile \(activeKey).")
            ))
        }
        if let activeKey, let entry = document.store[activeKey] {
            do {
                let profile = try TrioTherapyProfile(
                    name: activeName ?? TrioTherapyProfile.defaultName,
                    nightscoutProfile: entry,
                    documentUnits: document.units
                )
                activeProblem = TherapyProfileValidator.validate(profile, basalLimits: basalLimits)
            } catch {
                activeProblem = error.localizedDescription
            }
        } else {
            activeProblem = nil
        }
        // The active profile and Default count against the profile limit.
        let defaults = profiles.filter(\.isDefault)
        let activeIsDefault = (activeName ?? TrioTherapyProfile.defaultName) == TrioTherapyProfile.defaultName
        let room = TherapyProfileLimits.maxProfiles - 1 - (activeIsDefault ? defaults.count : max(defaults.count, 1))
        let others = profiles.filter { !$0.isDefault }
        for profile in others.dropFirst(max(room, 0)) {
            skipped.append(Skipped(
                name: profile.name,
                reason: String(localized: "Trio keeps at most \(TherapyProfileLimits.maxProfiles) profiles.")
            ))
        }
        self.profiles = defaults + others.prefix(max(room, 0))
        activeProfileName = activeName ?? TrioTherapyProfile.defaultName

        if document.unreadableScheduledSwitches > 0 {
            skipped.append(Skipped(
                name: String(localized: "Scheduled Switches"),
                reason: String(localized: "\(document.unreadableScheduledSwitches) scheduled switches could not be read.")
            ))
        }
        let importedNames = self.profiles.map(\.name) + [activeProfileName]
        var scheduledSwitches: [ScheduledProfileSwitch] = []
        for entry in document.scheduledSwitches {
            var entry = entry
            entry.profileName = trioName(entry.profileName)
            let label = String(
                localized: "\(entry.profileName) starts \(TherapyProfileValidator.weekdayName(entry.weekday)) \(TherapyProfileValidator.timeString(entry.time))"
            )
            if !importedNames.contains(entry.profileName) {
                skipped.append(Skipped(name: label, reason: String(localized: "Its profile was not imported.")))
            } else if let reason = TherapyProfileValidator.validateScheduledSwitches(scheduledSwitches + [entry]) {
                skipped.append(Skipped(name: label, reason: reason))
            } else {
                scheduledSwitches.append(entry)
            }
        }
        self.scheduledSwitches = scheduledSwitches
        self.skipped = skipped
    }
}

extension TrioTherapyProfile {
    /// A profile from a Nightscout store entry. Glucose values are converted to whole mg/dL from the entry's units, or
    /// the document's when the entry has none.
    init(name: String, nightscoutProfile entry: FetchedNightscoutProfile, documentUnits: String?) throws {
        let isMmolL = (entry.units ?? documentUnits ?? "").lowercased().contains("mmol")

        func seconds(_ item: NightscoutTimevalue) throws -> Int {
            if let seconds = item.timeAsSeconds { return seconds }
            let parts = item.time.split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2 else {
                throw TherapyProfileError.invalidValues(String(localized: "Invalid start time \(item.time)."))
            }
            return parts[0] * 3600 + parts[1] * 60
        }

        func glucose(_ value: Decimal) -> Decimal {
            isMmolL ? value.asMgdL : Trio.rounded(value, scale: 0, roundingMode: .plain)
        }

        guard entry.target_low.count == entry.target_high.count else {
            throw TherapyProfileError
                .invalidValues(String(localized: "Glucose Targets: each entry needs a start time, a low and a high value."))
        }
        var target: [TherapyTargetEntry] = []
        for (low, high) in zip(entry.target_low, entry.target_high) {
            let start = try seconds(low)
            guard try seconds(high) == start else {
                throw TherapyProfileError
                    .invalidValues(String(localized: "Glucose Targets: each entry needs a start time, a low and a high value."))
            }
            target.append(TherapyTargetEntry(seconds: start, low: glucose(low.value), high: glucose(high.value)))
        }

        self.init(
            name: name,
            basal: try entry.basal.map { TherapyScheduleEntry(seconds: try seconds($0), value: $0.value) },
            carbRatio: try entry.carbratio.map { TherapyScheduleEntry(seconds: try seconds($0), value: $0.value) },
            sensitivity: try entry.sens.map { TherapyScheduleEntry(seconds: try seconds($0), value: glucose($0.value)) },
            target: target
        )
    }
}

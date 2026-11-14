import CryptoKit
import Foundation

/// A weekly start of a therapy profile. The profile stays active until the next start.
struct ScheduledProfileSwitch: Equatable, Identifiable, Sendable {
    let id: String
    var profileName: String
    /// 1–7, Sunday = 1, as `Calendar` numbers weekdays.
    var weekday: Int
    /// Seconds from midnight, on a whole minute, in the time zone of the therapy schedules.
    var time: Int
    var paused: Bool

    init(id: String = UUID().uuidString, profileName: String, weekday: Int, time: Int, paused: Bool = false) {
        self.id = id
        self.profileName = profileName
        self.weekday = weekday
        self.time = time
        self.paused = paused
    }

    static let maxCount = 14

    /// The canonical string of one entry, as Loop and LoopFollow build it.
    var fingerprintCanonicalString: String {
        "profile=\(profileName);weekday=\(weekday);date=-;time=\(time);paused=\(paused)"
    }

    /// The occurrence on or before `date`, at most a week back.
    func occurrence(atOrBefore date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        for offset in 0 ... 7 {
            guard let candidate = occurrence(onDayOf: calendar.date(byAdding: .day, value: -offset, to: day), calendar: calendar)
            else { continue }
            if candidate <= date { return candidate }
        }
        return nil
    }

    /// The first occurrence after `date`.
    func occurrence(after date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        for offset in 0 ... 7 {
            guard let candidate = occurrence(onDayOf: calendar.date(byAdding: .day, value: offset, to: day), calendar: calendar)
            else { continue }
            if candidate > date { return candidate }
        }
        return nil
    }

    /// A time that does not exist on that day, at the start of daylight saving time, resolves to the first time after it.
    private func occurrence(onDayOf day: Date?, calendar: Calendar) -> Date? {
        guard let day, calendar.component(.weekday, from: day) == weekday else { return nil }
        return calendar.date(
            bySettingHour: time / 3600,
            minute: time % 3600 / 60,
            second: 0,
            of: day,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}

struct ScheduledProfileSwitchOccurrence: Equatable, Sendable {
    let entry: ScheduledProfileSwitch
    let date: Date
}

extension Array where Element == ScheduledProfileSwitch {
    /// The newest occurrence of an unpaused entry in (`after`, `upTo`].
    func newestOccurrence(after: Date, upTo: Date, calendar: Calendar) -> ScheduledProfileSwitchOccurrence? {
        filter { !$0.paused }
            .compactMap { entry in
                entry.occurrence(atOrBefore: upTo, calendar: calendar)
                    .map { ScheduledProfileSwitchOccurrence(entry: entry, date: $0) }
            }
            .filter { $0.date > after }
            .max { $0.date < $1.date }
    }

    /// The first occurrence of an unpaused entry after `date`.
    func nextOccurrence(after date: Date, calendar: Calendar) -> ScheduledProfileSwitchOccurrence? {
        filter { !$0.paused }
            .compactMap { entry in
                entry.occurrence(after: date, calendar: calendar).map { ScheduledProfileSwitchOccurrence(entry: entry, date: $0) }
            }
            .min { $0.date < $1.date }
    }

    /// Ordered as a week from Monday.
    var sortedByWeek: [ScheduledProfileSwitch] {
        sorted { lhs, rhs in
            let lhsDay = (lhs.weekday + 5) % 7
            let rhsDay = (rhs.weekday + 5) % 7
            if lhsDay != rhsDay { return lhsDay < rhsDay }
            return lhs.time != rhs.time ? lhs.time < rhs.time : lhs.id < rhs.id
        }
    }

    func renamingProfile(_ name: String, to newName: String) -> [ScheduledProfileSwitch] {
        map { entry in
            var entry = entry
            if entry.profileName == name { entry.profileName = newName }
            return entry
        }
    }

    func removingProfile(_ name: String) -> [ScheduledProfileSwitch] {
        filter { $0.profileName != name }
    }

    static func fingerprintCanonicalString(of entries: [ScheduledProfileSwitch]) -> String {
        entries.map(\.fingerprintCanonicalString).sorted().joined(separator: "|")
    }

    /// The first 16 hex characters of the SHA-256 of the canonical string, as Loop and LoopFollow compute it.
    var fingerprint: String {
        let digest = SHA256.hash(data: Data(Self.fingerprintCanonicalString(of: self).utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// The entries as the Nightscout profile document names them, with Default by its store key.
    var withStoreKeys: [ScheduledProfileSwitch] {
        renamingProfile(TrioTherapyProfile.defaultName, to: TrioTherapyProfile.defaultStoreKey)
    }

    /// Matches the fingerprint with Default named by its profile name or by its store key.
    func matchesFingerprint(_ fingerprint: String) -> Bool {
        let candidate = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return candidate == self.fingerprint || candidate == withStoreKeys.fingerprint
    }
}

/// The compact form in the Nightscout profile document and in remote commands. `paused` is left out when false.
extension ScheduledProfileSwitch: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case profileName = "profile"
        case weekday
        case date
        case time
        case paused
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard !container.contains(.date) else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "Scheduled switches on a date are not supported."
            )
        }
        id = try container.decode(String.self, forKey: .id)
        profileName = try container.decode(String.self, forKey: .profileName)
        weekday = try container.decode(Int.self, forKey: .weekday)
        time = try container.decode(Int.self, forKey: .time)
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(profileName, forKey: .profileName)
        try container.encode(weekday, forKey: .weekday)
        try container.encode(time, forKey: .time)
        if paused {
            try container.encode(true, forKey: .paused)
        }
    }
}

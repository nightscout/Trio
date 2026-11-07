import CoreData
import Foundation

extension TherapyProfileEntryStored {
    enum Kind: String {
        case basal
        case carbRatio
        case sensitivity
        case target
    }
}

extension TherapyProfileStored {
    @discardableResult static func insert(
        _ profile: TrioTherapyProfile,
        into context: NSManagedObjectContext
    ) -> TherapyProfileStored {
        let row = TherapyProfileStored(context: context)
        row.name = profile.name

        func entry(_ kind: TherapyProfileEntryStored.Kind, _ seconds: Int, _ value: Decimal, high: Decimal? = nil) {
            let entry = TherapyProfileEntryStored(context: context)
            entry.kind = kind.rawValue
            entry.seconds = Int32(seconds)
            entry.value = NSDecimalNumber(decimal: value)
            entry.high = high.map { NSDecimalNumber(decimal: $0) }
            entry.profile = row
        }
        profile.basal.forEach { entry(.basal, $0.seconds, $0.value) }
        profile.carbRatio.forEach { entry(.carbRatio, $0.seconds, $0.value) }
        profile.sensitivity.forEach { entry(.sensitivity, $0.seconds, $0.value) }
        profile.target.forEach { entry(.target, $0.seconds, $0.low, high: $0.high) }
        return row
    }

    var therapyProfile: TrioTherapyProfile? {
        guard let name else { return nil }
        let entries = (entries ?? []).sorted { $0.seconds < $1.seconds }

        func schedule(_ kind: TherapyProfileEntryStored.Kind) -> [TherapyScheduleEntry] {
            entries.filter { $0.kind == kind.rawValue }
                .map { TherapyScheduleEntry(seconds: Int($0.seconds), value: $0.value?.decimalValue ?? 0) }
        }

        return TrioTherapyProfile(
            name: name,
            basal: schedule(.basal),
            carbRatio: schedule(.carbRatio),
            sensitivity: schedule(.sensitivity),
            target: entries.filter { $0.kind == TherapyProfileEntryStored.Kind.target.rawValue }.map {
                TherapyTargetEntry(
                    seconds: Int($0.seconds),
                    low: $0.value?.decimalValue ?? 0,
                    high: $0.high?.decimalValue ?? $0.value?.decimalValue ?? 0
                )
            }
        )
    }
}

extension ScheduledProfileSwitchStored {
    @discardableResult static func insert(
        _ entry: ScheduledProfileSwitch,
        into context: NSManagedObjectContext
    ) -> ScheduledProfileSwitchStored {
        let row = ScheduledProfileSwitchStored(context: context)
        row.id = entry.id
        row.profileName = entry.profileName
        row.weekday = Int16(entry.weekday)
        row.time = Int32(entry.time)
        row.paused = entry.paused
        return row
    }

    var scheduledProfileSwitch: ScheduledProfileSwitch? {
        guard let id, let profileName else { return nil }
        return ScheduledProfileSwitch(id: id, profileName: profileName, weekday: Int(weekday), time: Int(time), paused: paused)
    }
}

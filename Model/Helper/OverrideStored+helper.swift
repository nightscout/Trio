import CoreData
import Foundation

extension NSPredicate {
    static var allOverridePresets: NSPredicate {
        NSPredicate(format: "isPreset == %@", true as NSNumber)
    }

    static var lastActiveOverride: NSPredicate {
        // For non-indefinite overrides, we still want to filter by date
        // For indefinite overrides, we want them regardless of date
        NSPredicate(
            format: "(date >= %@ OR indefinite == %@) AND enabled == %@",
            Date.oneDayAgo as NSDate,
            true as NSNumber,
            true as NSNumber
        )
    }
}

extension OverrideStored {
    static func fetch(_ predicate: NSPredicate, ascending: Bool, fetchLimit: Int? = nil) -> NSFetchRequest<OverrideStored> {
        let request = OverrideStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: ascending)]
        request.predicate = predicate
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return request
    }
}

extension OverrideStored {
    enum EventType: String, JSON {
        case nsExercise = "Exercise"
    }
}

extension OverrideStored {
    /// "SMBs Off", plus the hours when they're only scheduled off: "SMBs Off 22:00 – 06:00". Empty while SMBs are on.
    var smbOffText: String {
        guard smbIsOff || smbIsScheduledOff else { return "" }
        let hours = smbIsOff ? nil : Self.smbOffHours(start: start?.intValue ?? 0, end: end?.intValue ?? 0)
        return String(localized: "SMBs Off\(hours.map { " " + $0 } ?? "")")
    }

    /// The hours `DosingEngine` turns SMBs off: from start up to end, wrapping past midnight.
    /// Equal hours mean that one hour; 0 to 0 means all day, so there's no range to show.
    static func smbOffHours(start: Int, end: Int, locale: Locale = .autoupdatingCurrent) -> String? {
        if start == 0, end == 0 { return nil }
        let endHour = start == end ? (start + 1) % 24 : end
        return Date(hourOfDay: start).formattedTimeRange(to: Date(hourOfDay: endHour), locale: locale)
    }
}

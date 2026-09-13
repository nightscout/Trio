import CoreData
import Foundation

extension NSPredicate {
    static var allTempTargetPresets: NSPredicate {
        NSPredicate(format: "isPreset == %@", true as NSNumber)
    }

    static var lastActiveTempTarget: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND enabled == %@",
            date as NSDate,
            true as NSNumber
        )
    }

    static var tempTargetsForMainChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "(date >= %@ AND enabled == %@) OR (date >= %@ AND enabled == %@ AND isPreset == %@)",
            date as NSDate,
            true as NSNumber,
            Date() as NSDate,
            false as NSNumber,
            false as NSNumber
        )
    }

    static func tempTargetsForMainChart(since date: Date) -> NSPredicate {
        NSPredicate(
            format: "(date >= %@ AND enabled == %@) OR (date >= %@ AND enabled == %@)",
            date as NSDate,
            true as NSNumber,
            Date() as NSDate,
            false as NSNumber
        )
    }
}

extension TempTargetStored {
    /// Running temp targets and upcoming scheduled ones. Enacting a preset enables the preset row itself,
    /// so enabled presets are running temp targets; inactive presets are templates and never drawn.
    var isVisibleInChart: Bool {
        enabled || (!isPreset && (date ?? .distantPast) > Date())
    }

    static func fetch(_ predicate: NSPredicate, ascending: Bool, fetchLimit: Int? = nil) -> NSFetchRequest<TempTargetStored> {
        let request = TempTargetStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: ascending)]
        request.predicate = predicate
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return request
    }
}

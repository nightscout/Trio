import CoreData
import Foundation

extension OrefDetermination {
    static func fetch(_ predicate: NSPredicate = .predicateForOneDayAgo) -> NSFetchRequest<OrefDetermination> {
        let request = OrefDetermination.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OrefDetermination.deliverAt, ascending: false)]
        request.predicate = predicate
        request.fetchLimit = 1
        return request
    }
}

extension OrefDetermination {
    var reasonParts: [String] {
        reason?.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason?.components(separatedBy: "; ").last ?? ""
    }
}

extension NSPredicate {
    static var enactedDetermination: NSPredicate {
        let date = Date.halfHourAgo
        return NSPredicate(format: "enacted == %@ AND timestamp >= %@", true as NSNumber, date as NSDate)
    }

    static var determinationsForCobIobCharts: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "deliverAt >= %@", date as NSDate)
    }

    static var enactedDeterminationsNotYetUploadedToNightscout: NSPredicate {
        NSPredicate(
            format: "deliverAt >= %@ AND isUploadedToNS == %@ AND enacted == %@",
            Date.sixHoursAgo as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }

    static var suggestedDeterminationsNotYetUploadedToNightscout: NSPredicate {
        NSPredicate(
            format: "deliverAt >= %@ AND isUploadedToNS == %@ AND (enacted == %@ OR enacted == nil OR enacted != %@)",
            Date.sixHoursAgo as NSDate,
            false as NSNumber,
            true as NSNumber,
            true as NSNumber
        )
    }

    static var determinationsForStats: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "deliverAt >= %@", date as NSDate)
    }
}

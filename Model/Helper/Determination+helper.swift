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

extension Determination {
    var minPredBGFromReason: Decimal? {
        // Split reason into parts by semicolon and get first part
        let reasonParts = reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []

        // Find the part that contains "minPredBG"
        if let minPredBGPart = reasonParts.first(where: { $0.contains("minPredBG") }) {
            // Extract the number after "minPredBG"
            let components = minPredBGPart.components(separatedBy: "minPredBG ")
            if let valueComponent = components.dropFirst().first {
                // Get everything after "minPredBG " and convert to Decimal
                let valueString = valueComponent.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-").inverted)
                return Decimal(string: valueString)
            }
        }
        return nil
    }
}

extension OrefDetermination {
    var reasonParts: [String] {
        reason?.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason?.components(separatedBy: "; ").last ?? ""
    }

    var minPredBGFromReason: Decimal? {
        // Find the part that contains "minPredBG"
        if let minPredBGPart = reasonParts.first(where: { $0.contains("minPredBG") }) {
            // Extract the number after "minPredBG"
            let components = minPredBGPart.components(separatedBy: "minPredBG ")
            if let valueComponent = components.dropFirst().first {
                // Get everything after "minPredBG " and convert to Decimal
                let valueString = valueComponent.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-").inverted)
                return Decimal(string: valueString)
            }
        }
        return nil
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
            Date.oneDayAgo as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }

    static var suggestedDeterminationsNotYetUploadedToNightscout: NSPredicate {
        NSPredicate(
            format: "deliverAt >= %@ AND isUploadedToNS == %@ AND (enacted == %@ OR enacted == nil OR enacted != %@)",
            Date.oneDayAgo as NSDate,
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

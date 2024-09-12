import CoreData
import Foundation

enum MainChartHelper {
    // Calculates the glucose value thats the nearest to parameter 'time'
    /// -Returns: A NSManagedObject of GlucoseStored
    /// it is thread safe as everything is executed on the main thread
    static func timeToNearestGlucose(glucoseValues: [GlucoseStored], time: TimeInterval) -> GlucoseStored? {
        guard !glucoseValues.isEmpty else {
            return nil
        }

        var low = 0
        var high = glucoseValues.count - 1
        var closestGlucose: GlucoseStored?

        // binary search to find next glucose
        while low <= high {
            let mid = low + (high - low) / 2
            let midTime = glucoseValues[mid].date?.timeIntervalSince1970 ?? 0

            if midTime == time {
                return glucoseValues[mid]
            } else if midTime < time {
                low = mid + 1
            } else {
                high = mid - 1
            }

            // update if necessary
            if closestGlucose == nil || abs(midTime - time) < abs(closestGlucose!.date?.timeIntervalSince1970 ?? 0 - time) {
                closestGlucose = glucoseValues[mid]
            }
        }

        return closestGlucose
    }

    enum Config {
        static let bolusSize: CGFloat = 5
        static let bolusScale: CGFloat = 1.8
        static let carbsSize: CGFloat = 5
        static let maxCarbSize: CGFloat = 30
        static let carbsScale: CGFloat = 0.3
        static let fpuSize: CGFloat = 10
        static let maxGlucose = 270
        static let minGlucose = 45
    }

    static var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter
    }

    static var carbsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    static func bolusOffset(units: GlucoseUnits) -> Decimal {
        units == .mgdL ? 30 : 1.66
    }

    static func calculateDuration(objectID: NSManagedObjectID, context: NSManagedObjectContext) -> TimeInterval? {
        do {
            if let override = try context.existingObject(with: objectID) as? OverrideStored,
               let overrideDuration = override.duration as? Double, overrideDuration != 0
            {
                return TimeInterval(overrideDuration * 60) // return seconds
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to calculate Override Target with error: \(error.localizedDescription)"
            )
        }
        return nil
    }

    static func calculateTarget(objectID: NSManagedObjectID, context: NSManagedObjectContext) -> Decimal? {
        do {
            if let override = try context.existingObject(with: objectID) as? OverrideStored,
               let overrideTarget = override.target, overrideTarget != 0
            {
                return overrideTarget.decimalValue
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to calculate Override Target with error: \(error.localizedDescription)"
            )
        }
        return nil
    }
}

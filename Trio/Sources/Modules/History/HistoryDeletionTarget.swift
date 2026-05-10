import CoreData
import Foundation

extension History {
    enum DeletionTarget: Identifiable {
        case glucose(GlucoseStored)
        case insulin(PumpEventStored)
        case carbs(CarbEntryStored)

        var id: NSManagedObjectID {
            switch self {
            case let .glucose(glucose): return glucose.objectID
            case let .insulin(pumpEvent): return pumpEvent.objectID
            case let .carbs(carbEntry): return carbEntry.objectID
            }
        }

        func title(units _: GlucoseUnits) -> String {
            switch self {
            case .glucose:
                return String(localized: "Delete Glucose?", comment: "Alert title for deleting glucose")
            case .insulin:
                return String(localized: "Delete Insulin?", comment: "Alert title for deleting insulin")
            case let .carbs(carbEntry):
                if carbEntry.fpuID == nil {
                    return String(localized: "Delete Carbs?", comment: "Alert title for deleting carbs")
                }
                return carbEntry.isFPU
                    ? String(localized: "Delete Carbs Equivalents?", comment: "Alert title for deleting carb equivalents")
                    : String(localized: "Delete Carbs?", comment: "Alert title for deleting carbs")
            }
        }

        func message(units: GlucoseUnits) -> String? {
            switch self {
            case let .glucose(glucose):
                let glucoseToDisplay = units == .mgdL
                    ? glucose.glucose.description
                    : Int(glucose.glucose).formattedAsMmolL
                return Formatter.dateFormatter.string(from: glucose.date ?? Date())
                    + ", " + glucoseToDisplay + " " + units.rawValue
            case let .insulin(pumpEvent):
                var text = Formatter.dateFormatter.string(from: pumpEvent.timestamp ?? Date())
                    + ", "
                    + (Formatter.decimalFormatterWithThreeFractionDigits.string(from: pumpEvent.bolus?.amount ?? 0) ?? "0")
                    + String(localized: " U", comment: "Insulin unit")
                if let bolus = pumpEvent.bolus, bolus.isSMB {
                    text += String(localized: " SMB", comment: "Super Micro Bolus indicator in delete alert")
                }
                return text
            case let .carbs(carbEntry):
                if carbEntry.fpuID == nil {
                    return Formatter.dateFormatter.string(from: carbEntry.date ?? Date())
                        + ", "
                        + (Formatter.decimalFormatterWithTwoFractionDigits.string(for: carbEntry.carbs) ?? "0")
                        + String(localized: " g", comment: "gram of carbs")
                }
                return String(
                    localized: "All FPUs and the carbs of the meal will be deleted.",
                    comment: "Alert message for meal deletion"
                )
            }
        }
    }
}

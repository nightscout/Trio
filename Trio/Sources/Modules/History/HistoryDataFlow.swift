import CoreData
import Foundation
import HealthKit
import SwiftUI

enum History {
    enum Config {}

    enum TreatmentType: String, CaseIterable {
        case bolus = "Bolus"
        case externalBolus = "External Bolus"
        case smb = "SMB"
        case tempBasal = "Temp Basal"
        case suspend = "Suspend"
        case other = "Other"

        var displayName: String {
            switch self {
            case .bolus:
                return String(localized: "Bolus")
            case .externalBolus:
                return String(localized: "External Bolus")
            case .smb:
                return String(localized: "SMB")
            case .tempBasal:
                return String(localized: "Temp Basal")
            case .suspend:
                return String(localized: "Suspend")
            case .other:
                return String(localized: "Other")
            }
        }
    }

    enum Mode: String, Hashable, Identifiable, CaseIterable {
        case treatments
        case meals
        case glucose
        case adjustments

        var id: String { rawValue }

        var name: String {
            switch self {
            case .treatments:
                return String(localized: "Treatments", comment: "History Mode")
            case .meals:
                return String(localized: "Meals", comment: "History Mode")
            case .glucose:
                return String(localized: "Glucose", comment: "History Mode")
            case .adjustments:
                return String(localized: "Adjustments", comment: "History Mode")
            }
        }
    }

    enum DataType: String, Equatable {
        case carbs
        case fpus
        case bolus
        case tempBasal
        case tempTarget
        case suspend
        case resume

        var name: String {
            switch self {
            case .carbs:
                return String(localized: "Carbs", comment: "Treatment type")
            case .fpus:
                return String(localized: "Protein / Fat", comment: "Treatment type")
            case .bolus:
                return String(localized: "Bolus", comment: "Treatment type")
            case .tempBasal:
                return String(localized: "Temp Basal", comment: "Treatment type")
            case .tempTarget:
                return String(localized: "Temp Target", comment: "Treatment type")
            case .suspend:
                return String(localized: "Suspend", comment: "Treatment type")
            case .resume:
                return String(localized: "Resume", comment: "Treatment type")
            }
        }
    }
}

protocol HistoryProvider: Provider {
    func deleteCarbsFromNightscout(withID id: String)
    func deleteInsulinFromNightscout(withID id: String)
    func deleteManualGlucoseFromNightscout(withID id: String)
    func deleteGlucoseFromHealth(withSyncID id: String)
    func deleteMealDataFromHealth(byID id: String, sampleType: HKSampleType)
    func deleteInsulinFromHealth(withSyncID id: String)
    func deleteInsulinFromTidepool(withSyncId id: String, amount: Decimal, at: Date)
    func deleteCarbsFromTidepool(withSyncId id: UUID, carbs: Decimal, at: Date, enteredBy: String)
}

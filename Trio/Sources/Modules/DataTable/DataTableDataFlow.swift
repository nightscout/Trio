import CoreData
import Foundation
import HealthKit
import SwiftUI

enum DataTable {
    enum Config {}

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

    class Treatment: Identifiable, Hashable, Equatable {
        let id: String
        let idPumpEvent: String?
        let units: GlucoseUnits
        let type: DataType
        let date: Date
        let amount: Decimal?
        let secondAmount: Decimal?
        let duration: Decimal?
        let isFPU: Bool?
        let fpuID: String?
        let note: String?
        let isSMB: Bool?
        let isExternal: Bool?

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var tempTargetFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        init(
            units: GlucoseUnits,
            type: DataType,
            date: Date,
            amount: Decimal? = nil,
            secondAmount: Decimal? = nil,
            duration: Decimal? = nil,
            id: String? = nil,
            idPumpEvent: String? = nil,
            isFPU: Bool? = nil,
            fpuID: String? = nil,
            note: String? = nil,
            isSMB: Bool? = nil,
            isExternal: Bool? = nil
        ) {
            self.units = units
            self.type = type
            self.date = date
            self.amount = amount
            self.secondAmount = secondAmount
            self.duration = duration
            self.id = id ?? UUID().uuidString
            self.idPumpEvent = idPumpEvent
            self.isFPU = isFPU
            self.fpuID = fpuID
            self.note = note
            self.isSMB = isSMB
            self.isExternal = isExternal
        }

        static func == (lhs: Treatment, rhs: Treatment) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        var amountText: String {
            guard let amount = amount else {
                return ""
            }

            if amount == 0, duration == 0 {
                return "Cancel temp"
            }

            switch type {
            case .carbs:
                return numberFormatter
                    .string(from: amount as NSNumber)! + String(localized: " g", comment: "gram of carbs")
            case .fpus:
                return numberFormatter
                    .string(from: amount as NSNumber)! + String(localized: " g", comment: "gram of carb equilvalents")
            case .bolus:
                var bolusText = " "
                if isSMB ?? false {}
                else if isExternal ?? false {
                    bolusText += String(localized: "External", comment: "External Insulin")
                } else {
                    bolusText += String(localized: "Manual", comment: "Manual Bolus")
                }

                return numberFormatter
                    .string(from: amount as NSNumber)! + String(localized: " U", comment: "Insulin unit") + bolusText
            case .tempBasal:
                return numberFormatter
                    .string(from: amount as NSNumber)! + String(localized: " U/hr", comment: "Unit insulin per hour")
            case .tempTarget:
                var converted = amount
                if units == .mmolL {
                    converted = converted.asMmolL
                }

                guard var secondAmount = secondAmount else {
                    return numberFormatter.string(from: converted as NSNumber)! + " \(units.rawValue)"
                }
                if units == .mmolL {
                    secondAmount = secondAmount.asMmolL
                }

                return tempTargetFormater.string(from: converted as NSNumber)! + " - " + tempTargetFormater
                    .string(from: secondAmount as NSNumber)! + " \(units.rawValue)"
            case .resume,
                 .suspend:
                return type.name
            }
        }

        var color: Color {
            switch type {
            case .carbs:
                return .loopYellow
            case .fpus:
                return .orange.opacity(0.5)
            case .bolus:
                return Color.insulin
            case .tempBasal:
                return Color.insulin.opacity(0.4)
            case .resume,
                 .suspend,
                 .tempTarget:
                return .loopGray
            }
        }

        var durationText: String? {
            guard let duration = duration, duration > 0 else {
                return nil
            }
            return numberFormatter.string(from: duration as NSNumber)! + " min"
        }
    }

    class Glucose: Identifiable, Hashable, Equatable {
        static func == (lhs: DataTable.Glucose, rhs: DataTable.Glucose) -> Bool {
            lhs.glucose == rhs.glucose
        }

        let glucose: BloodGlucose

        init(glucose: BloodGlucose) {
            self.glucose = glucose
        }

        var id: String { glucose.id }
    }
}

protocol DataTableProvider: Provider {
    func deleteCarbsFromNightscout(withID id: String)
    func deleteInsulinFromNightscout(withID id: String)
    func deleteManualGlucoseFromNightscout(withID id: String)
    func deleteGlucoseFromHealth(withSyncID id: String)
    func deleteMealDataFromHealth(byID id: String, sampleType: HKSampleType)
    func deleteInsulinFromHealth(withSyncID id: String)
}

import Foundation
import SwiftUI

extension History {
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
    }

    class Glucose: Identifiable, Hashable, Equatable {
        static func == (lhs: History.Glucose, rhs: History.Glucose) -> Bool {
            lhs.glucose == rhs.glucose
        }

        let glucose: BloodGlucose

        init(glucose: BloodGlucose) {
            self.glucose = glucose
        }

        var id: String { glucose.id }
    }
}

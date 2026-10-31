import Foundation
import SwiftUI

enum TherapySettingsEditor {
    struct Item: Identifiable, Equatable, Hashable {
        var id = UUID()
        var time: TimeInterval = 0 // seconds since start of day
        var value: Decimal = 0

        init(time: TimeInterval, value: Decimal) {
            self.time = time
            self.value = value
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.time == rhs.time && lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(time)
            hasher.combine(value)
        }
    }

    enum Unit: String, CaseIterable {
        case mmolLPerUnit
        case mgdLPerUnit
        case unitPerHour
        case unitPerDay
        case gramPerUnit
        case mmolL
        case mgdL

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .mmolLPerUnit:
                return String(localized: "mmol/L/U")
            case .mgdLPerUnit:
                return String(localized: "mg/dL/U")
            case .unitPerHour:
                return String(localized: "U/hr")
            case .unitPerDay:
                return String(localized: "U/day")
            case .gramPerUnit:
                return String(localized: "g/U")
            case .mmolL:
                return "mmol/L"
            case .mgdL:
                return "mg/dL"
            }
        }

        /// Fully spoken unit for VoiceOver. Localizable per case (so translations stay correct)
        /// and grammatical — the denominator "unit" is singular, unlike the tokenized speller,
        /// which is fed English keys and would pass translated abbreviations through unchanged.
        var spokenName: String {
            switch self {
            case .mmolLPerUnit:
                return String(localized: "millimoles per liter per unit", comment: "Accessibility: spoken unit")
            case .mgdLPerUnit:
                return String(localized: "milligrams per deciliter per unit", comment: "Accessibility: spoken unit")
            case .unitPerHour:
                return String(localized: "units per hour", comment: "Accessibility: spoken unit")
            case .unitPerDay:
                return String(localized: "units per day", comment: "Accessibility: spoken unit")
            case .gramPerUnit:
                return String(localized: "grams per unit", comment: "Accessibility: spoken unit")
            case .mmolL:
                return String(localized: "millimoles per liter", comment: "Accessibility: spoken unit")
            case .mgdL:
                return String(localized: "milligrams per deciliter", comment: "Accessibility: spoken unit")
            }
        }
    }

    enum TherapyType {
        case basalRate
        case carbRatio
        case insulinSensitivity
        case bloodGlucoseTarget

        var chartColor: Color {
            switch self {
            case .basalRate: Color.purple
            case .carbRatio: Color.orange
            case .insulinSensitivity: Color.cyan
            case .bloodGlucoseTarget: Color.green
            }
        }

        var chartAccessibilityLabel: String {
            switch self {
            case .basalRate: String(localized: "Basal rate profile chart, 24 hours")
            case .carbRatio: String(localized: "Carb ratio profile chart, 24 hours")
            case .insulinSensitivity: String(localized: "Insulin sensitivity profile chart, 24 hours")
            case .bloodGlucoseTarget: String(localized: "Glucose target profile chart, 24 hours")
            }
        }

        var title: String {
            switch self {
            case .basalRate: String(localized: "Basal Rates")
            case .carbRatio: String(localized: "Carb Ratios")
            case .insulinSensitivity: String(localized: "Insulin Sensitivities")
            case .bloodGlucoseTarget: String(localized: "Glucose Targets")
            }
        }

        var chartShowsArea: Bool {
            switch self {
            case .bloodGlucoseTarget: false
            default: true
            }
        }

        var chartYScale: ClosedRange<Decimal>? {
            switch self {
            case .bloodGlucoseTarget: Decimal(72) ... Decimal(180)
            default: nil
            }
        }

        var unit: Unit {
            switch self {
            case .basalRate: .unitPerHour
            case .carbRatio: .gramPerUnit
            case .insulinSensitivity: .mgdLPerUnit
            case .bloodGlucoseTarget: .mgdL
            }
        }

        func getUnit(for glucoseUnits: GlucoseUnits) -> Unit {
            switch self {
            case .insulinSensitivity: glucoseUnits == .mgdL ? .mgdLPerUnit : .mmolLPerUnit
            case .bloodGlucoseTarget: glucoseUnits == .mgdL ? .mgdL : .mmolL
            default: unit
            }
        }

        var totalUnit: Unit? {
            switch self {
            case .basalRate: .unitPerDay
            default: nil
            }
        }
    }
}

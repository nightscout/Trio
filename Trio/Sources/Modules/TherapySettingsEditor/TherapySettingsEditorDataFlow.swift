import Foundation

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
            case .gramPerUnit:
                return String(localized: "g/U")
            case .mmolL:
                return "mmol/L"
            case .mgdL:
                return "mg/dL"
            }
        }
    }

    protocol StateModel: ObservableObject {
        var therapyItems: [Item] { get set }
        var unit: Unit { get }
        var timeOptions: [TimeInterval] { get }
        var valueOptions: [Decimal] { get }
        var hasChanges: Bool { get }
        var isSaving: Bool { get }

        func validate()
        func save()
        func getTherapyItems() -> [Item]
        func updateFromTherapyItems(_ therapyItems: [Item])
    }
}

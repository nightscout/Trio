import AppIntents
import Foundation

/// class to display the Glucose units
@available(iOS 16.0, *) enum UnitList: String, AppEnum {
    static let title = LocalizedStringResource("Unit", table: "ShortcutsDetail")
    //  static var defaultQuery = UnitQuery()

    case mgdL
    case mmolL

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: .init("Unit", table: "ShortcutsDetail"))

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] =
        [
            .mgdL: .init(title: LocalizedStringResource("mg/dL", table: "ShortcutsDetail")),
            .mmolL: .init(title: LocalizedStringResource("mmol/L", table: "ShortcutsDetail"))
        ]
}

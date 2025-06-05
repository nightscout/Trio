import Foundation
import SwiftUI

enum Adjustments {
    enum Config {}

    enum Tab: String, Hashable, Identifiable, CaseIterable {
        case overrides
        case tempTargets

        var id: String { rawValue }

        var name: String {
            switch self {
            case .overrides:
                return String(localized: "Overrides", comment: "Selected Tab")
            case .tempTargets:
                return String(localized: "Temp Targets", comment: "Selected Tab")
            }
        }
    }
}

protocol AdjustmentsProvider: Provider {}

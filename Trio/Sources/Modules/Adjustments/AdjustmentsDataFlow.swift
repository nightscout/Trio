import Foundation
import SwiftUI

enum Adjustments {
    enum Config {}

    enum Tab: String, Hashable, Identifiable, CaseIterable {
        case overrides
        case tempTargets

        var id: String { rawValue }

        var name: String {
            var name: String = ""
            switch self {
            case .overrides:
                name = "Overrides"
            case .tempTargets:
                name = "Temp Targets"
            }

            return NSLocalizedString(name, comment: "Selected Tab")
        }
    }
}

protocol AdjustmentsProvider: Provider {}

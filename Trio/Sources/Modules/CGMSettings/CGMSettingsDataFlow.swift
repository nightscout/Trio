import LoopKit
import SwiftUI

enum CGMSettings {
    enum Config {}
}

protocol CGMSettingsProvider: Provider {}

/// `cgmStatusHighlight` reduced to message + tier — what the home UI needs.
struct CgmDisplayState: Equatable {
    let localizedMessage: String
    let status: CgmDisplayStatus
}

enum CgmDisplayStatus {
    case normal
    case warning
    case critical

    var color: Color {
        switch self {
        case .critical: return .critical
        case .warning: return .warning
        case .normal: return .loopAccent
        }
    }

    static func from(_ state: LoopKit.DeviceStatusHighlightState) -> CgmDisplayStatus {
        switch state {
        case .normalCGM,
             .normalPump:
            return .normal
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }
}

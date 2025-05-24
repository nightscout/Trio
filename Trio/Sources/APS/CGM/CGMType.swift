import Foundation

enum CGMType: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case none
    case nightscout
    case xdrip
    case enlite
    case plugin

    #if DEBUG_SIMULATORS
        case simulator
    #endif

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .nightscout:
            return "Nightscout as CGM"
        case .xdrip:
            return "xDrip4iOS"
        case .enlite:
            return "Medtronic Enlite"
        case .plugin:
            return "Plugin CGM"
        #if DEBUG_SIMULATORS
            case .simulator:
                return String(localized: "Glucose Simulator", comment: "Glucose Simulator CGM type")
        #endif
        }
    }

    var appURL: URL? {
        switch self {
        case .enlite,
             .nightscout,
             .none:
            return nil
        case .xdrip:
            return URL(string: "xdripswift://")!
        case .plugin:
            return nil
        #if DEBUG_SIMULATORS
            case .simulator:
                return nil
        #endif
        }
    }

    var externalLink: URL? {
        switch self {
        case .xdrip:
            return URL(string: "https://xdrip4ios.readthedocs.io/")!
        default: return nil
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            return String(localized: "None", comment: "No CGM selected")
        case .nightscout:
            return String(localized: "Uses your Nightscout as CGM", comment: "Online or internal server")
        case .xdrip:
            return String(
                localized:
                "Using shared app group with external CGM app xDrip4iOS",
                comment: "Shared app group xDrip4iOS"
            )
        case .enlite:
            return String(localized: "Minilink transmitter", comment: "Minilink transmitter")
        case .plugin:
            return String(localized: "Plugin CGM", comment: "Plugin CGM")
        #if DEBUG_SIMULATORS
            case .simulator:
                return String(localized: "Glucose Simulator for Demo Only", comment: "Simple simulator")
        #endif
        }
    }
}

enum GlucoseDataError: Error {
    case noData
    case unreliableData
}

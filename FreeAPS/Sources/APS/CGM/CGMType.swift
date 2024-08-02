import Foundation

enum CGMType: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }
    case none
    case nightscout
    case xdrip
    case simulator
    case enlite
    case plugin

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .nightscout:
            return "Nightscout"
        case .xdrip:
            return "xDrip4iOS"
        case .simulator:
            return NSLocalizedString("Glucose Simulator", comment: "Glucose Simulator CGM type")
        case .enlite:
            return "Medtronic Enlite"
        case .plugin:
            return "plugin CGM"
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
        case .simulator:
            return nil
        case .plugin:
            return nil
        }
    }

    var externalLink: URL? {
        switch self {
        case .xdrip:
            return URL(string: "https://github.com/JohanDegraeve/xdripswift")!
        default: return nil
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            return NSLocalizedString("None", comment: "No CGM choiced")
        case .nightscout:
            return NSLocalizedString("Online or internal server", comment: "Online or internal server")
        case .xdrip:
            return NSLocalizedString(
                "Using shared app group with external CGM app xDrip4iOS",
                comment: "Shared app group xDrip4iOS"
            )
        case .simulator:
            return NSLocalizedString("Simple simulator", comment: "Simple simulator")
        case .enlite:
            return NSLocalizedString("Minilink transmitter", comment: "Minilink transmitter")
        case .plugin:
            return NSLocalizedString("Plugin CGM", comment: "Plugin CGM")
        }
    }
}

enum GlucoseDataError: Error {
    case noData
    case unreliableData
}

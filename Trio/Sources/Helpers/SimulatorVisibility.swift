import Foundation

enum SimulatorVisibility: String {
    case visible = "0"
    case hidden = "1"

    var isHidden: Bool {
        self == .hidden
    }

    init(rawValue: String) {
        self = rawValue == "1" ? .hidden : .visible
    }
}

extension Bundle {
    var simulatorVisibility: SimulatorVisibility {
        SimulatorVisibility(rawValue: object(forInfoDictionaryKey: "HideSimulator") as? String ?? "0")
    }
}

import Foundation

enum WatchComplicationValue: String, CaseIterable, Identifiable, Codable, Hashable {
    case nothing
    case iob
    case cob
    case delta
    case loopAge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nothing: return String(localized: "Nothing", comment: "Complication slot shows nothing")
        case .iob: return String(localized: "IOB", comment: "")
        case .cob: return String(localized: "COB", comment: "")
        case .delta: return String(localized: "Delta", comment: "")
        case .loopAge: return String(localized: "Loop Age", comment: "Minutes since the last loop")
        }
    }
}

enum WatchComplicationDefaults {
    static let cornerValue: WatchComplicationValue = .iob
    static let secondaryValue: WatchComplicationValue = .delta
    static let staleMinutes = 15
    static let staleMinutesRange = 10 ... 30
    static let staleMinutesStep = 5
    static let gaugeRangeMgdl = 45.0 ... 290.0
    static let gaugeRangeMmol = 2.5 ... 16.0

    static func clampedStaleMinutes(_ minutes: Int) -> Int {
        min(max(minutes, staleMinutesRange.lowerBound), staleMinutesRange.upperBound)
    }
}

struct ComplicationRingStop: Codable, Hashable, Sendable {
    var location: Double
    var colorHex: String
}

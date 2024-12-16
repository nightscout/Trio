import CoreData
import SwiftUI

struct ContactTrickEntry: Hashable, Sendable {
    var id = UUID()
    var name: String = ""
    var layout: ContactTrickLayout = .single
    var ring: ContactTrickLargeRing = .none
    var primary: ContactTrickValue = .glucose
    var top: ContactTrickValue = .none
    var bottom: ContactTrickValue = .none
    var contactId: String? = nil
    var darkMode: Bool = false
    var ringWidth: RingWidth = .regular
    var ringGap: RingGap = .small
    var fontSize: FontSize = .regular
    var secondaryFontSize: FontSize = .small
    var fontWeight: Font.Weight = .medium
    var fontWidth: Font.Width = .standard
    var managedObjectID: NSManagedObjectID?

    // Convert `fontWeight` to a String for Core Data storage
    var fontWeightString: String {
        fontWeight.asString
    }

    // Initialize `fontWeight` from a String
    static func fontWeight(from string: String) -> Font.Weight {
        Font.Weight.fromString(string)
    }

    // Convert `fontWidth` to a String for Core Data storage
    var fontWidthString: String {
        fontWidth.asString
    }

    // Initialize `fontWidth` from a String
    static func fontWidth(from string: String) -> Font.Width {
        Font.Width.fromString(string)
    }

    enum FontSize: Int, Codable, Sendable, CaseIterable {
        case tiny = 200
        case small = 250
        case regular = 300
        case large = 400

        var displayName: String {
            switch self {
            case .tiny: return "Tiny"
            case .small: return "Small"
            case .regular: return "Regular"
            case .large: return "Large"
            }
        }
    }

    enum RingWidth: Int, Codable, Sendable, CaseIterable {
        case tiny = 3
        case small = 5
        case regular = 7
        case medium = 10
        case large = 15

        var displayName: String {
            switch self {
            case .tiny: return "Tiny"
            case .small: return "Small"
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    enum RingGap: Int, Codable, Sendable, CaseIterable {
        case tiny = 1
        case small = 2
        case regular = 3
        case medium = 4
        case large = 5

        var displayName: String {
            switch self {
            case .tiny: return "Tiny"
            case .small: return "Small"
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }
}

protocol ContactTrickObserver: Sendable {
    // TODO: is this required?
//    func basalProfileDidChange(_ entry: [ContactTrickEntry])
}

enum ContactTrickValue: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case none
    case glucose
    case eventualBG
    case delta
    case trend
    case lastLoopDate
    case cob
    case iob
    case ring

    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("NoneContactValue", comment: "")
        case .glucose:
            return NSLocalizedString("GlucoseContactValue", comment: "")
        case .eventualBG:
            return NSLocalizedString("EventualBGContactValue", comment: "")
        case .delta:
            return NSLocalizedString("DeltaContactValue", comment: "")
        case .trend:
            return NSLocalizedString("TrendContactValue", comment: "")
        case .lastLoopDate:
            return NSLocalizedString("LastLoopTimeContactValue", comment: "")
        case .cob:
            return NSLocalizedString("COBContactValue", comment: "")
        case .iob:
            return NSLocalizedString("IOBContactValue", comment: "")
        case .ring:
            return NSLocalizedString("LoopStatusContactValue", comment: "")
        }
    }
}

enum ContactTrickLayout: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case single
    case split

    var displayName: String {
        switch self {
        case .single:
            return NSLocalizedString("Single", comment: "")
        case .split:
            return NSLocalizedString("Split", comment: "")
        }
    }
}

enum ContactTrickLargeRing: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case none
    case loop
    case iob
    case cob
    case iobcob

    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("DontShowRing", comment: "")
        case .loop:
            return NSLocalizedString("LoopStatusRing", comment: "")
        case .iob:
            return NSLocalizedString("IOBRing", comment: "")
        case .cob:
            return NSLocalizedString("COBRing", comment: "")
        case .iobcob:
            return NSLocalizedString("IOB+COBRing", comment: "")
        }
    }
}

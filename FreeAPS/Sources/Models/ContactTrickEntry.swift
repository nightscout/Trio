import SwiftUI

struct ContactTrickEntry: Hashable {
    var layout: ContactTrickLayout = .single
    var ring1: ContactTrickLargeRing = .none
    var primary: ContactTrickValue = .glucose
    var top: ContactTrickValue = .none
    var bottom: ContactTrickValue = .none
    var contactId: String? = nil
    var darkMode: Bool = true
    var ringWidth: ringWidth = .regular
    var ringGap: ringGap = .small
    var fontSize: fontSize = .regular
    var secondaryFontSize: fontSize = .small
    var fontWeight: Font.Weight = .medium
    var fontWidth: Font.Width = .standard

    enum fontSize: Int {
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

    enum ringWidth: Int {
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

    enum ringGap: Int {
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

protocol ContactTrickObserver {
    func basalProfileDidChange(_ entry: [ContactTrickEntry])
}

//
// extension ContactTrickEntry {
//    private enum CodingKeys: String, CodingKey {
//        case layout
//        case ring1
//        case primary
//        case top
//        case bottom
//        case contactId
//        case darkMode
//        case ringWidth
//        case ringGap
//        case fontSize
//        case secondaryFontSize
//        case fontWeight
//        case fontWidth
//    }
//
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        let layout = try container.decodeIfPresent(ContactTrickLayout.self, forKey: .layout) ?? .single
//        let ring1 = try container.decodeIfPresent(ContactTrickLargeRing.self, forKey: .ring1) ?? .none
//        let primary = try container.decodeIfPresent(ContactTrickValue.self, forKey: .primary) ?? .glucose
//        let top = try container.decodeIfPresent(ContactTrickValue.self, forKey: .top) ?? .none
//        let bottom = try container.decodeIfPresent(ContactTrickValue.self, forKey: .bottom) ?? .none
//        let contactId = try container.decodeIfPresent(String.self, forKey: .contactId)
//        let darkMode = try container.decodeIfPresent(Bool.self, forKey: .darkMode) ?? true
//        let ringWidth = try container.decodeIfPresent(Int.self, forKey: .ringWidth) ?? 7
//        let ringGap = try container.decodeIfPresent(Int.self, forKey: .ringGap) ?? 2
//        let fontSize = try container.decodeIfPresent(Int.self, forKey: .fontSize) ?? 300
//        let secondaryFontSize = try container.decodeIfPresent(Int.self, forKey: .secondaryFontSize) ?? 250
//        let fontWeight = try container.decodeIfPresent(Font.Weight.self, forKey: .fontWeight) ?? .medium
//        let fontWidth = try container.decodeIfPresent(Font.Width.self, forKey: .fontWidth) ?? .standard
//
//        self = ContactTrickEntry(
//            layout: layout,
//            ring1: ring1,
//            primary: primary,
//            top: top,
//            bottom: bottom,
//            contactId: contactId,
//            darkMode: darkMode,
//            ringWidth: ringWidth,
//            ringGap: ringGap,
//            fontSize: fontSize,
//            secondaryFontSize: secondaryFontSize,
//            fontWeight: fontWeight,
//            fontWidth: fontWidth
//        )
//    }
// }


struct ContactTrickEntry: JSON, Equatable, Hashable {
    var layout: ContactTrickLayout = .single
    var ring1: ContactTrickLargeRing = .none
    var primary: ContactTrickValue = .glucose
    var top: ContactTrickValue = .none
    var bottom: ContactTrickValue = .none
    var contactId: String? = nil
    var darkMode: Bool = true
    var ringWidth: Int = 7
    var ringGap: Int = 2
    var fontSize: Int = 300
    var secondaryFontSize: Int = 250
    var fontName: String = "Default Font"
    var fontWeight: FontWeight = .medium
    var fontTracking: FontTracking = .normal

    func isDefaultFont() -> Bool {
        fontName == "Default Font"
    }
}

protocol ContactTrickObserver {
    func basalProfileDidChange(_ entry: [ContactTrickEntry])
}

extension ContactTrickEntry {
    private enum CodingKeys: String, CodingKey {
        case layout
        case ring1
        case primary
        case top
        case bottom
        case contactId
        case darkMode
        case ringWidth
        case ringGap
        case fontSize
        case secondaryFontSize
        case fontName
        case fontWeight
        case fontTracking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let layout = try container.decodeIfPresent(ContactTrickLayout.self, forKey: .layout) ?? .single
        let ring1 = try container.decodeIfPresent(ContactTrickLargeRing.self, forKey: .ring1) ?? .none
        let primary = try container.decodeIfPresent(ContactTrickValue.self, forKey: .primary) ?? .glucose
        let top = try container.decodeIfPresent(ContactTrickValue.self, forKey: .top) ?? .none
        let bottom = try container.decodeIfPresent(ContactTrickValue.self, forKey: .bottom) ?? .none
        let contactId = try container.decodeIfPresent(String.self, forKey: .contactId)
        let darkMode = try container.decodeIfPresent(Bool.self, forKey: .darkMode) ?? true
        let ringWidth = try container.decodeIfPresent(Int.self, forKey: .ringWidth) ?? 7
        let ringGap = try container.decodeIfPresent(Int.self, forKey: .ringGap) ?? 2
        let fontSize = try container.decodeIfPresent(Int.self, forKey: .fontSize) ?? 300
        let secondaryFontSize = try container.decodeIfPresent(Int.self, forKey: .secondaryFontSize) ?? 250
        let fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "Default Font"
        let fontWeight = try container.decodeIfPresent(FontWeight.self, forKey: .fontWeight) ?? .regular
        let fontTracking = try container.decodeIfPresent(FontTracking.self, forKey: .fontTracking) ?? .normal

        self = ContactTrickEntry(
            layout: layout,
            ring1: ring1,
            primary: primary,
            top: top,
            bottom: bottom,
            contactId: contactId,
            darkMode: darkMode,
            ringWidth: ringWidth,
            ringGap: ringGap,
            fontSize: fontSize,
            secondaryFontSize: secondaryFontSize,
            fontName: fontName,
            fontWeight: fontWeight,
            fontTracking: fontTracking
        )
    }
}

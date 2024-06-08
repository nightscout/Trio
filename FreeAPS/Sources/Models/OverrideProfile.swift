import Foundation

struct OverrideProfile: JSON, Identifiable, Equatable, Hashable {
    var id = UUID().uuidString
    var name: String? = nil
    var createdAt: Date? = nil
    var duration: Decimal? = nil {
        didSet {
            indefinite = (duration == nil)
        }
    }

    var indefinite: Bool? = false
    var percentage: Double? = 100
    var target: Decimal? = 0
    var advancedSettings: Bool? = false
    var smbIsOff: Bool? = false
    var isfAndCr: Bool? = false
    var isf: Bool? = false
    var cr: Bool? = false
    var smbIsScheduledOff: Bool? = false
    var start: Decimal? = 0
    var end: Decimal? = 0

    var smbMinutes: Decimal? = nil
    var uamMinutes: Decimal? = nil
    var enteredBy: String? = OverrideProfile.manual
    var reason: String?

    static let manual = "Trio"
    static let custom = "Temp override"
    static let cancel = "Cancel"

    var displayName: String {
        if let name = name, name != "" {
            return name
        } else {
            return OverrideProfile.custom
        }
    }

    static func == (lhs: OverrideProfile, rhs: OverrideProfile) -> Bool {
        lhs.createdAt == rhs.createdAt && lhs.indefinite == rhs.indefinite && lhs.duration == rhs.duration
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func cancel(at date: Date) -> OverrideProfile {
        OverrideProfile(
            name: OverrideProfile.cancel,
            createdAt: date,
            duration: nil,
            indefinite: false,
            percentage: 100.0,
            target: 0,
            advancedSettings: false,
            smbIsOff: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: nil,
            uamMinutes: nil,
            enteredBy: OverrideProfile.manual,
            reason: OverrideProfile.cancel
        )
    }
}

extension OverrideProfile {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case createdAt
        case advancedSettings
        case cr
        case duration
        case end
        case indefinite
        case isf
        case isfAndCr
        case percentage
        case smbIsScheduledOff
        case smbIsOff
        case smbMinutes
        case start
        case target
        case uamMinutes
        case enteredBy
        case reason
    }
}

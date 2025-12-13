import Foundation

enum TherapyProfileList {
    enum Config {}
}

protocol TherapyProfileListProvider: Provider {
    var profiles: [TherapyProfile] { get }
    var activeProfile: TherapyProfile? { get }
    var isManualOverrideActive: Bool { get }
}

import Foundation

enum TherapyProfileEditor {
    enum Config {
        /// The profile being edited
        static var profile: TherapyProfile?
        /// Whether this is a new profile
        static var isNew: Bool = false
    }
}

protocol TherapyProfileEditorProvider: Provider {
    var profile: TherapyProfile? { get }
    var isNew: Bool { get }
    var allProfiles: [TherapyProfile] { get }
    var units: GlucoseUnits { get }
}

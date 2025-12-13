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

    // Current active settings for copy feature
    var hasCurrentActiveSettings: Bool { get }
    var currentBasalProfile: [BasalProfileEntry] { get }
    var currentInsulinSensitivities: InsulinSensitivities? { get }
    var currentCarbRatios: CarbRatios? { get }
    var currentBGTargets: BGTargets? { get }
}

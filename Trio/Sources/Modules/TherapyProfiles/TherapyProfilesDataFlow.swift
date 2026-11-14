enum TherapyProfiles {
    enum Config {}

    enum Editor: Hashable {
        case basal
        case carbRatio
        case sensitivity
        case target
    }
}

protocol TherapyProfilesProvider: Provider {}

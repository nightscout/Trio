enum Bolus {
    enum Config {}
}

protocol BolusProvider: Provider {
    func getPumpSettings() async -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
    func getCarbRatios() async -> CarbRatios
    func getBGTarget() async -> BGTargets
    func getISFValues() async -> InsulinSensitivities
}

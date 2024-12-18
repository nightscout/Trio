enum Treatments {
    enum Config {}
}

protocol TreatmentsProvider: Provider {
    func getPumpSettings() async -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
    func getCarbRatios() async -> CarbRatios
    func getBGTarget() async -> BGTargets
    func getISFValues() async -> InsulinSensitivities
}

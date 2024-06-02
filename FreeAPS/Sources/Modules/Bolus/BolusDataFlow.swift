enum Bolus {
    enum Config {}
}

protocol BolusProvider: Provider {
    func pumpSettings() -> PumpSettings
}

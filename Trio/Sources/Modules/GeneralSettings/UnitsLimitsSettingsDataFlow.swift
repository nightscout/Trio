import Combine

enum UnitsLimitsSettings {
    enum Config {}
}

protocol UnitsLimitsSettingsProvider: Provider {
    func settings() -> PumpSettings
    func save(settings: PumpSettings) -> AnyPublisher<Void, Error>
}

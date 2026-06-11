import Observation

extension Telemetry {
    @Observable final class StateModel: BaseStateModel<Provider> {}
}

extension Telemetry.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {}
}

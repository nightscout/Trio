enum UserInterfaceSettings {
    enum Config {}
}

protocol UserInterfaceSettingsProvider: Provider {
    func getBGTargets() async -> BGTargets
}

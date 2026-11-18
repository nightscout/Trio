extension UserInterfaceSettings {
    final class Provider: BaseProvider, UserInterfaceSettingsProvider {
        func getBGTargets() async -> BGTargets {
            therapyProfileStorage.liveSettings.bgTargets
        }
    }
}

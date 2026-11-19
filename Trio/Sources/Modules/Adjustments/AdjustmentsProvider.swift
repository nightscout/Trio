extension Adjustments {
    final class Provider: BaseProvider, AdjustmentsProvider {
        func getBGTargets() async -> BGTargets {
            therapyProfileStorage.liveSettings.bgTargets
        }
    }
}

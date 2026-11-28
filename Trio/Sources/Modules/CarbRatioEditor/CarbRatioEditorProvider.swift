import Combine

extension CarbRatioEditor {
    final class Provider: BaseProvider, CarbRatioEditorProvider {
        var profile: CarbRatios {
            therapyProfileStorage.liveSettings.carbRatios
        }
    }
}

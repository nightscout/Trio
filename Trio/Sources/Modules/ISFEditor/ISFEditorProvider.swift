import Foundation

extension ISFEditor {
    final class Provider: BaseProvider, ISFEditorProvider {
        var profile: InsulinSensitivities {
            therapyProfileStorage.liveSettings.insulinSensitivities
        }
    }
}

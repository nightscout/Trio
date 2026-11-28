import Foundation

extension TargetsEditor {
    final class Provider: BaseProvider, TargetsEditorProvider {
        var profile: BGTargets {
            therapyProfileStorage.liveSettings.bgTargets
        }
    }
}

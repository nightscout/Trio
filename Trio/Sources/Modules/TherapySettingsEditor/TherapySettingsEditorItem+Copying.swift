import Foundation

/// Convenience extension to ease copying of existing `TherapySettingItem`s
extension TherapySettingsEditor.Item {
    init(copying item: TherapySettingsEditor.Item, newID: Bool = false) {
        id = newID ? UUID() : item.id
        time = item.time
        value = item.value
    }
}

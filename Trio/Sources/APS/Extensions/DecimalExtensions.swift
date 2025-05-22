import Foundation

extension Decimal {
    func clamp(to pickerSetting: PickerSetting) -> Decimal {
        max(min(self, pickerSetting.max), pickerSetting.min)
    }
}

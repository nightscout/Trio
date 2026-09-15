import Foundation

extension Decimal {
    /// Clamps the value into the range a picker allows.
    ///
    /// Lives here rather than with the general `DecimalExtensions` helpers so that
    /// those stay free of UI-layer types like `PickerSetting`.
    func clamp(to pickerSetting: PickerSetting) -> Decimal {
        max(min(self, pickerSetting.max), pickerSetting.min)
    }
}

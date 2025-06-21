import Foundation

extension Decimal {
    func clamp(to pickerSetting: PickerSetting) -> Decimal {
        max(min(self, pickerSetting.max), pickerSetting.min)
    }
}

extension Collection where Element == Decimal {
    /// Returns the arithmetic mean, or zero if empty.
    var mean: Decimal {
        guard !isEmpty else { return .zero }
        return reduce(.zero, +) / Decimal(count)
    }
}

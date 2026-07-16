import Foundation

extension Decimal {
    func clamp(to pickerSetting: PickerSetting) -> Decimal {
        max(min(self, pickerSetting.max), pickerSetting.min)
    }

    /// Converts a `Double` to a `Decimal` using JSON style conversion
    init(algorithmValue value: Double) {
        self = Decimal(string: value.description) ?? Decimal(value)
    }
}

extension Collection where Element == Decimal {
    /// Returns the arithmetic mean, or zero if empty.
    var mean: Decimal {
        guard !isEmpty else { return .zero }
        return reduce(.zero, +) / Decimal(count)
    }
}

// Trio
// DecimalExtensions.swift
// Created by Sam King on 2025-05-19.

import Foundation

extension Decimal {
    func clamp(to pickerSetting: PickerSetting) -> Decimal {
        max(min(self, pickerSetting.max), pickerSetting.min)
    }
}

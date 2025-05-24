//
// Trio
// MealSettingsStateModel.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-02-07.
// Most contributions by Jon Mårtensson and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import SwiftUI

extension MealSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Published var units: GlucoseUnits = .mgdL
        @Published var useFPUconversion: Bool = true
        @Published var maxCarbs: Decimal = 250
        @Published var maxFat: Decimal = 250
        @Published var maxProtein: Decimal = 250
        @Published var individualAdjustmentFactor: Decimal = 0.5
        @Published var timeCap: Decimal = 8
        @Published var minuteInterval: Decimal = 30
        @Published var delay: Decimal = 60
        @Published var maxMealAbsorptionTime: Decimal = 6

        override func subscribe() {
            units = settingsManager.settings.units

            subscribeSetting(\.maxCarbs, on: $maxCarbs) { maxCarbs = $0 }
            subscribeSetting(\.maxFat, on: $maxFat) { maxFat = $0 }
            subscribeSetting(\.maxProtein, on: $maxProtein) { maxProtein = $0 }

            subscribePreferencesSetting(\.maxMealAbsorptionTime, on: $maxMealAbsorptionTime) { maxMealAbsorptionTime = $0 }

            subscribeSetting(\.useFPUconversion, on: $useFPUconversion) { useFPUconversion = $0 }

            // "Fat and Protein Delay"
            subscribeSetting(\.delay, on: $delay) { delay = $0 }

            // "Maximum Duration"
            subscribeSetting(\.timeCap, on: $timeCap) { timeCap = $0 }

            // "Spread Interval"
            subscribeSetting(\.minuteInterval, on: $minuteInterval) { minuteInterval = $0 }

            // "Fat and Protein Percentage"
            subscribeSetting(\.individualAdjustmentFactor, on: $individualAdjustmentFactor) { individualAdjustmentFactor = $0 }
        }
    }
}

extension MealSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}

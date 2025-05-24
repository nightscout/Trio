//
// Trio
// TargetBehavoirStateModel.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Robert on 2025-02-25.
// Most contributions by Deniz Cengiz and Robert.
//
// Documentation available under: https://triodocs.org/

import SwiftUI

extension TargetBehavoir {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL

        @Published var highTemptargetRaisesSensitivity: Bool = false
        @Published var lowTemptargetLowersSensitivity: Bool = false
        @Published var sensitivityRaisesTarget: Bool = false
        @Published var resistanceLowersTarget: Bool = false
        @Published var halfBasalExerciseTarget: Decimal = 160
        @Published var autosensMax: Decimal = 1

        override func subscribe() {
            units = settingsManager.settings.units
            autosensMax = settingsManager.preferences.autosensMax
            subscribePreferencesSetting(\.highTemptargetRaisesSensitivity, on: $highTemptargetRaisesSensitivity) {
                highTemptargetRaisesSensitivity = $0 }
            subscribePreferencesSetting(\.lowTemptargetLowersSensitivity, on: $lowTemptargetLowersSensitivity) {
                lowTemptargetLowersSensitivity = $0 }
            subscribePreferencesSetting(\.sensitivityRaisesTarget, on: $sensitivityRaisesTarget) { sensitivityRaisesTarget = $0 }
            subscribePreferencesSetting(\.resistanceLowersTarget, on: $resistanceLowersTarget) { resistanceLowersTarget = $0 }
            subscribePreferencesSetting(\.halfBasalExerciseTarget, on: $halfBasalExerciseTarget) { halfBasalExerciseTarget = $0 }
        }
    }
}

extension TargetBehavoir.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}

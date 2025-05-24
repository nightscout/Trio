//
// Trio
// LiveActivitySettingsStateModel.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Combine
import SwiftUI

extension LiveActivitySettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useLiveActivity = false
        @Published var lockScreenView: LockScreenView = .simple
        override func subscribe() {
            units = settingsManager.settings.units
            subscribeSetting(\.useLiveActivity, on: $useLiveActivity) { useLiveActivity = $0 }
            subscribeSetting(\.lockScreenView, on: $lockScreenView) { lockScreenView = $0 }
        }
    }
}

extension LiveActivitySettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}

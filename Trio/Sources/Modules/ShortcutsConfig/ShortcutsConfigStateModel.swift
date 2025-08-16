//
//  ShortcutsConfigStateModel.swift
//  Trio
//
//  Created by Pierre LAGARDE on 01/05/2024.
//
import SwiftUI

extension ShortcutsConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var units: GlucoseUnits = .mgdL
        @Published var allowBolusByShortcuts: Bool = false
        @Published var maxBolusByShortcuts: BolusShortcutLimit = .notAllowed

        override func subscribe() {
            units = settingsManager.settings.units

            subscribeSetting(\.bolusShortcut, on: $maxBolusByShortcuts) {
                maxBolusByShortcuts = ($0 == .notAllowed) ? .limitBolusMax : $0
                allowBolusByShortcuts = ($0 != .notAllowed)
            }

            $allowBolusByShortcuts.receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    if !value {
                        // the bolus is not allowed
                        self?.settingsManager.settings.bolusShortcut = .notAllowed
                    } else {
                        if let bs = self?.maxBolusByShortcuts {
                            self?.settingsManager.settings.bolusShortcut = bs
                        } else {
                            self?.settingsManager.settings.bolusShortcut = .limitBolusMax
                        }
                    }
                }
                .store(in: &lifetime)
        }
    }
}

extension ShortcutsConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}

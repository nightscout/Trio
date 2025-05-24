//
// Trio
// WatchConfigProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Pierre L.
//
// Documentation available under: https://triodocs.org/

import Foundation

extension WatchConfig {
    final class Provider: BaseProvider, WatchConfigProvider {
        @Injected() private var settingsManager: SettingsManager!
        private let processQueue = DispatchQueue(label: "WatchDeviceProvider.processQueue")

        var preferences: Preferences {
            settingsManager.preferences
        }

        func savePreferences(_ preferences: Preferences) {
            processQueue.async {
                var prefs = preferences
                prefs.timestamp = Date()
                self.storage.save(prefs, as: OpenAPS.Settings.preferences)
            }
        }
    }
}

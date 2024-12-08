import Foundation
import LoopKit
import Swinject

protocol SettingsManager: AnyObject {
    var settings: FreeAPSSettings { get set }
    var preferences: Preferences { get set }
    var pumpSettings: PumpSettings { get }
    func updateInsulinCurve(_ insulinType: InsulinType?)
}

protocol SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings)
}

protocol PreferencesObserver {
    func preferencesDidChange(_: Preferences)
}

final class BaseSettingsManager: SettingsManager, Injectable {
    @Injected() var broadcaster: Broadcaster!
    @Injected() var storage: FileStorage!

    @SyncAccess var settings: FreeAPSSettings {
        didSet {
            if oldValue != settings {
                saveSettings()
                DispatchQueue.main.async {
                    self.broadcaster.notify(SettingsObserver.self, on: .main) {
                        $0.settingsDidChange(self.settings)
                    }
                }
            }
        }
    }

    @SyncAccess var preferences: Preferences {
        didSet {
            if oldValue != preferences {
                savePreferences()
                DispatchQueue.main.async {
                    self.broadcaster.notify(PreferencesObserver.self, on: .main) {
                        $0.preferencesDidChange(self.preferences)
                    }
                }
            }
        }
    }

    private func saveSettings() {
        storage.save(settings, as: OpenAPS.FreeAPS.settings)
    }

    private func savePreferences() {
        storage.save(preferences, as: OpenAPS.Settings.preferences)
    }

    init(resolver: Resolver) {
        let storage = resolver.resolve(FileStorage.self)!
        settings = storage.retrieve(OpenAPS.FreeAPS.settings, as: FreeAPSSettings.self)
            ?? FreeAPSSettings(from: OpenAPS.defaults(for: OpenAPS.FreeAPS.settings))
            ?? FreeAPSSettings()

        preferences =
            storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
                ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                ?? Preferences()

        injectServices(resolver)
    }

    var pumpSettings: PumpSettings {
        storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
            ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
            ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
    }

    func updateInsulinCurve(_ insulinType: InsulinType?) {
        var prefs = preferences

        switch insulinType {
        case .apidra,
             .humalog,
             .novolog:
            prefs.curve = .rapidActing

        case .fiasp,
             .lyumjev:
            prefs.curve = .ultraRapid
        default:
            prefs.curve = .rapidActing
        }

        preferences = prefs
        savePreferences()
    }
}

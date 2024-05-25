import SwiftUI

extension OverrideProfilesConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var percentage: Double = 100
        @Published var isEnabled = false
        @Published var _indefinite = true
        @Published var duration: Decimal = 0
        @Published var target: Decimal = 0
        @Published var override_target: Bool = false
        @Published var smbIsOff: Bool = false
        @Published var id: String = ""
        @Published var profileName: String = ""
        @Published var isPreset: Bool = false
        @Published var presets: [OverrideProfil] = []
        @Published var advancedSettings: Bool = false
        @Published var isfAndCr: Bool = true
        @Published var isf: Bool = true
        @Published var cr: Bool = true
        @Published var smbIsScheduledOff: Bool = false
        @Published var start: Decimal = 0
        @Published var end: Decimal = 23
        @Published var smbMinutes: Decimal = 0
        @Published var uamMinutes: Decimal = 0
        @Published var defaultSmbMinutes: Decimal = 0
        @Published var defaultUamMinutes: Decimal = 0

        @Injected() private var overrideStorage: OverrideStorage!

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes
            presets = overrideStorage.presets()
        }

        func saveSettings() {
            let overrideToSave = OverrideProfil(
                name: profileName,
                createdAt: Date(),
                duration: _indefinite ? nil : duration,
                indefinite: _indefinite,
                percentage: percentage,
                target: override_target ? (units == .mmolL ? target.asMgdL : target) : 0,
                advancedSettings: advancedSettings,
                smbIsOff: smbIsOff,
                isfAndCr: isfAndCr,
                isf: isfAndCr ? false : isf,
                cr: isfAndCr ? false : cr,
                smbIsScheduledOff: smbIsScheduledOff,
                start: smbIsScheduledOff ? start : nil,
                end: smbIsScheduledOff ? end : nil,
                smbMinutes: smbMinutes,
                uamMinutes: uamMinutes
            )

            overrideStorage.storeOverride([overrideToSave])
        }

        func savePreset() {
            let overridePresetToSave = OverrideProfil(
                name: profileName,
                duration: _indefinite ? nil : duration,
                indefinite: _indefinite,
                percentage: percentage,
                target: override_target ? (units == .mmolL ? target.asMgdL : target) : 0,
                advancedSettings: advancedSettings,
                smbIsOff: smbIsOff,
                isfAndCr: isfAndCr,
                isf: isfAndCr ? false : isf,
                cr: isfAndCr ? false : cr,
                smbIsScheduledOff: smbIsScheduledOff,
                start: smbIsScheduledOff ? start : nil,
                end: smbIsScheduledOff ? end : nil,
                smbMinutes: smbMinutes,
                uamMinutes: uamMinutes
            )

            overrideStorage.storeOverridePresets([overridePresetToSave])
            presets = overrideStorage.presets()
        }

        func updatePreset(_ presetId: String) {
            let overridePresetToSave = OverrideProfil(
                id: presetId,
                name: profileName,
                duration: _indefinite ? nil : duration,
                indefinite: _indefinite,
                percentage: percentage,
                target: override_target ? (units == .mmolL ? target.asMgdL : target) : 0,
                advancedSettings: advancedSettings,
                smbIsOff: smbIsOff,
                isfAndCr: isfAndCr,
                isf: isfAndCr ? false : isf,
                cr: isfAndCr ? false : cr,
                smbIsScheduledOff: smbIsScheduledOff,
                start: smbIsScheduledOff ? start : nil,
                end: smbIsScheduledOff ? end : nil,
                smbMinutes: smbMinutes,
                uamMinutes: uamMinutes
            )

            overrideStorage.storeOverridePresets([overridePresetToSave])
            presets = overrideStorage.presets()
        }

        func selectProfile(id_: String) {
            guard id_ != "" else { return }
            _ = overrideStorage.applyOverridePreset(id_)
        }

        func reset() {
            percentage = 100
            isEnabled = false
            _indefinite = true
            duration = 0
            target = 0
            override_target = false
            smbIsOff = false
            id = ""
            profileName = ""
            advancedSettings = false
            isfAndCr = true
            isf = true
            cr = true
            smbIsScheduledOff = false
            start = 0
            end = 23
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes
        }

        func displayCurrentOverride() {
            guard let currentOverride = overrideStorage.current() else {
                isEnabled = false
                return
            }
            isEnabled = true
            displayOverrideProfil(profil: currentOverride)
        }

        func displayOverrideProfil(profil: OverrideProfil) {
            percentage = profil.percentage ?? 100
            _indefinite = profil.indefinite ?? true
            duration = profil.duration ?? 0
            smbIsOff = profil.smbIsOff ?? false
            advancedSettings = profil.advancedSettings ?? false
            isfAndCr = profil.isfAndCr ?? true
            smbIsScheduledOff = profil.smbIsScheduledOff ?? false

            if advancedSettings {
                if !isfAndCr {
                    isf = profil.isf ?? false
                    cr = profil.cr ?? false
                }
                if smbIsScheduledOff {
                    start = profil.start ?? 0
                    end = profil.end ?? 0
                }

                smbMinutes = profil.smbMinutes ?? defaultSmbMinutes
                uamMinutes = profil.uamMinutes ?? defaultUamMinutes
            }

            let overrideTarget = profil.target ?? 0
            if overrideTarget != 0 {
                override_target = true
                target = units == .mmolL ? overrideTarget.asMmolL : overrideTarget
            }
            if !_indefinite {
                let durationOverride = profil.duration ?? 0
                let date = profil.createdAt ?? Date()
                duration = max(0, durationOverride + Decimal(Date().distance(to: date).minutes))
            }
        }

        func cancelProfile() {
            _indefinite = true
            isEnabled = false
            percentage = 100
            duration = 0
            target = 0
            override_target = false
            smbIsOff = false
            advancedSettings = false
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes

            _ = overrideStorage.cancelCurrentOverride()
        }

        func removeOverrideProfile(presetId: String) {
            overrideStorage.deleteOverridePreset(presetId)
        }
    }
}

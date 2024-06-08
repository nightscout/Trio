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
        @Published var presets: [OverrideProfile] = []
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

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        override func subscribe() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes
            presets = overrideStorage.presets()
        }

        func saveSettings() {
            let overrideToSave = OverrideProfile(
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
            let overridePresetToSave = OverrideProfile(
                name: profileName,
                duration: _indefinite ? nil : duration,
                indefinite: _indefinite,
                percentage: percentage,
                target: override_target ? (units == .mmolL ? target.asMgdL : target) : nil,
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

        func loadCurrentProfil() {
            guard let currentOverride = overrideStorage.current() else {
                isEnabled = false
                return
            }

            isEnabled = true
            populateSettings(from: currentOverride)
        }

        func populateSettings(from preset: OverrideProfile) {
            percentage = preset.percentage ?? 100
            _indefinite = preset.indefinite ?? true
            duration = preset.duration ?? 0
            smbIsOff = preset.smbIsOff ?? false
            advancedSettings = preset.advancedSettings ?? false
            isfAndCr = preset.isfAndCr ?? true
            smbIsScheduledOff = preset.smbIsScheduledOff ?? false

            if advancedSettings {
                if !isfAndCr {
                    isf = preset.isf ?? false
                    cr = preset.cr ?? false
                }
                if smbIsScheduledOff {
                    start = preset.start ?? 0
                    end = preset.end ?? 0
                }

                smbMinutes = preset.smbMinutes ?? defaultSmbMinutes
                uamMinutes = preset.uamMinutes ?? defaultUamMinutes
            }

            let overrideTarget = preset.target ?? 0
            if overrideTarget != 0 {
                override_target = true
                target = units == .mmolL ? overrideTarget.asMmolL : overrideTarget
            }
            if !_indefinite {
                let durationOverride = preset.duration ?? 0
                let date = preset.createdAt ?? Date()
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
            presets = overrideStorage.presets()
        }

        func updatePreset(_ presetId: String) {
            let overridePresetToSave = OverrideProfile(
                id: presetId,
                name: profileName,
                duration: _indefinite ? nil : duration,
                indefinite: _indefinite,
                percentage: percentage,
                target: override_target ? (units == .mmolL ? target.asMgdL : target) : nil,
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
    }
}

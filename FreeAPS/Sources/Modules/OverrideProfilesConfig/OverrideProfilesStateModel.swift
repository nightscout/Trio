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
//        @Published var selection: OverrideProfil?
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

        func selectProfile(id_: String) {
            guard id_ != "" else { return }
            _ = overrideStorage.applyOverridePreset(id_)
        }

        func savedSettings() {
            guard let currentOverride = overrideStorage.current() else {
                isEnabled = false
                return
            }

            isEnabled = true
            percentage = currentOverride.percentage ?? 100
            _indefinite = currentOverride.indefinite ?? true
            duration = currentOverride.duration ?? 0
            smbIsOff = currentOverride.smbIsOff ?? false
            advancedSettings = currentOverride.advancedSettings ?? false
            isfAndCr = currentOverride.isfAndCr ?? true
            smbIsScheduledOff = currentOverride.smbIsScheduledOff ?? false

            if advancedSettings {
                if !isfAndCr {
                    isf = currentOverride.isf ?? false
                    cr = currentOverride.cr ?? false
                }
                if smbIsScheduledOff {
                    start = currentOverride.start ?? 0
                    end = currentOverride.end ?? 0
                }

                smbMinutes = currentOverride.smbMinutes ?? defaultSmbMinutes
                uamMinutes = currentOverride.uamMinutes ?? defaultUamMinutes
            }

            let overrideTarget = currentOverride.target ?? 0
            if overrideTarget != 0 {
                override_target = true
                target = units == .mmolL ? overrideTarget.asMmolL : overrideTarget
            }
            if !_indefinite {
                let durationOverride = currentOverride.duration ?? 0
                let date = currentOverride.createdAt ?? Date()
                duration = max(0, durationOverride + Decimal(Date().distance(to: date).minutes))
            }
        }

        func populateSettings(from preset: OverridePresets) {
            profileName = preset.name ?? ""
            percentage = preset.percentage
            duration = (preset.duration ?? 0) as Decimal
            _indefinite = preset.indefinite
            override_target = preset.target != nil
            if let targetValue = preset.target as NSDecimalNumber? {
                target = units == .mmolL ? (targetValue as Decimal).asMmolL : targetValue as Decimal
            } else {
                target = 0
            }
            advancedSettings = preset.advancedSettings
            smbIsOff = preset.smbIsOff
            smbIsScheduledOff = preset.smbIsScheduledOff
            isf = preset.isf
            cr = preset.cr
            smbMinutes = (preset.smbMinutes ?? 0) as Decimal
            uamMinutes = (preset.uamMinutes ?? 0) as Decimal
            isfAndCr = preset.isfAndCr
            start = (preset.start ?? 0) as Decimal
            end = (preset.end ?? 0) as Decimal
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

        func updatePreset(_ preset: OverridePresets) {
            let context = CoreDataStack.shared.persistentContainer.viewContext
            context.performAndWait {
                preset.name = profileName
                preset.percentage = percentage
                preset.duration = NSDecimalNumber(decimal: duration)
                let targetValue = override_target ? (units == .mmolL ? target.asMgdL : target) : nil
                preset.target = targetValue != nil ? NSDecimalNumber(decimal: targetValue!) : nil
                preset.indefinite = _indefinite
                preset.advancedSettings = advancedSettings
                preset.smbIsOff = smbIsOff
                preset.smbIsScheduledOff = smbIsScheduledOff
                preset.isf = isf
                preset.cr = cr
                preset.smbMinutes = NSDecimalNumber(decimal: smbMinutes)
                preset.uamMinutes = NSDecimalNumber(decimal: uamMinutes)
                preset.isfAndCr = isfAndCr
                try? context.save()
            }
        }
    }
}

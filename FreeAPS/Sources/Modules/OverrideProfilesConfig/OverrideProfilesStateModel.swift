import CoreData
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
        @Published var presets: [OverridePresets] = []
        @Published var selection: OverridePresets?
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

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            presets = [OverridePresets(context: coredataContext)]
        }

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        func saveSettings() {
            coredataContext.perform { [self] in
                let saveOverride = Override(context: self.coredataContext)
                saveOverride.duration = self.duration as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentage
                saveOverride.enabled = true
                saveOverride.smbIsOff = self.smbIsOff
                if self.isPreset {
                    saveOverride.isPreset = true
                    saveOverride.id = id
                } else { saveOverride.isPreset = false }
                saveOverride.date = Date()
                if override_target {
                    if units == .mmolL {
                        target = target.asMgdL
                    }
                    saveOverride.target = target as NSDecimalNumber
                } else { saveOverride.target = 0 }

                if advancedSettings {
                    saveOverride.advancedSettings = true

                    if !isfAndCr {
                        saveOverride.isfAndCr = false
                        saveOverride.isf = isf
                        saveOverride.cr = cr
                    } else { saveOverride.isfAndCr = true }
                    if smbIsScheduledOff {
                        saveOverride.smbIsScheduledOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { saveOverride.smbIsScheduledOff = false }

                    saveOverride.smbMinutes = smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = uamMinutes as NSDecimalNumber
                }
                try? self.coredataContext.save()
            }
        }

        func savePreset() {
            coredataContext.perform { [self] in
                let saveOverride = OverridePresets(context: self.coredataContext)
                saveOverride.duration = self.duration as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentage
                saveOverride.smbIsOff = self.smbIsOff
                saveOverride.name = self.profileName
                id = UUID().uuidString
                self.isPreset.toggle()
                saveOverride.id = id
                saveOverride.date = Date()
                if override_target {
                    saveOverride.target = (
                        units == .mmolL
                            ? target.asMgdL
                            : target
                    ) as NSDecimalNumber
                } else { saveOverride.target = 0 }

                if advancedSettings {
                    saveOverride.advancedSettings = true

                    if !isfAndCr {
                        saveOverride.isfAndCr = false
                        saveOverride.isf = isf
                        saveOverride.cr = cr
                    } else { saveOverride.isfAndCr = true }
                    if smbIsScheduledOff {
                        saveOverride.smbIsScheduledOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { smbIsScheduledOff = false }

                    saveOverride.smbMinutes = smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = uamMinutes as NSDecimalNumber
                }
                try? self.coredataContext.save()
            }
        }

        func selectProfile(id_: String) {
            guard id_ != "" else { return }
            coredataContext.performAndWait {
                var profileArray = [OverridePresets]()
                let requestProfiles = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
                try? profileArray = coredataContext.fetch(requestProfiles)

                guard let profile = profileArray.filter({ $0.id == id_ }).first else { return }

                let saveOverride = Override(context: self.coredataContext)
                saveOverride.duration = (profile.duration ?? 0) as NSDecimalNumber
                saveOverride.indefinite = profile.indefinite
                saveOverride.percentage = profile.percentage
                saveOverride.enabled = true
                saveOverride.smbIsOff = profile.smbIsOff
                saveOverride.isPreset = true
                saveOverride.date = Date()
                saveOverride.target = profile.target
                saveOverride.id = id_

                if profile.advancedSettings {
                    saveOverride.advancedSettings = true
                    if !isfAndCr {
                        saveOverride.isfAndCr = false
                        saveOverride.isf = profile.isf
                        saveOverride.cr = profile.cr
                    } else { saveOverride.isfAndCr = true }
                    if profile.smbIsScheduledOff {
                        saveOverride.smbIsScheduledOff = true
                        saveOverride.start = profile.start
                        saveOverride.end = profile.end
                    } else { saveOverride.smbIsScheduledOff = false }

                    saveOverride.smbMinutes = (profile.smbMinutes ?? 0) as NSDecimalNumber
                    saveOverride.uamMinutes = (profile.uamMinutes ?? 0) as NSDecimalNumber
                }
                try? self.coredataContext.save()
            }
        }

        func savedSettings() {
            coredataContext.performAndWait {
                var overrideArray = [Override]()
                let requestEnabled = Override.fetchRequest() as NSFetchRequest<Override>
                let sortIsEnabled = NSSortDescriptor(key: "date", ascending: false)
                requestEnabled.sortDescriptors = [sortIsEnabled]
                // requestEnabled.fetchLimit = 1
                try? overrideArray = coredataContext.fetch(requestEnabled)
                isEnabled = overrideArray.first?.enabled ?? false
                percentage = overrideArray.first?.percentage ?? 100
                _indefinite = overrideArray.first?.indefinite ?? true
                duration = (overrideArray.first?.duration ?? 0) as Decimal
                smbIsOff = overrideArray.first?.smbIsOff ?? false
                advancedSettings = overrideArray.first?.advancedSettings ?? false
                isfAndCr = overrideArray.first?.isfAndCr ?? true
                smbIsScheduledOff = overrideArray.first?.smbIsScheduledOff ?? false

                if advancedSettings {
                    if !isfAndCr {
                        isf = overrideArray.first?.isf ?? false
                        cr = overrideArray.first?.cr ?? false
                    }
                    if smbIsScheduledOff {
                        start = (overrideArray.first?.start ?? 0) as Decimal
                        end = (overrideArray.first?.end ?? 0) as Decimal
                    }

                    if (overrideArray[0].smbMinutes as Decimal?) != nil {
                        smbMinutes = (overrideArray.first?.smbMinutes ?? 30) as Decimal
                    }

                    if (overrideArray[0].uamMinutes as Decimal?) != nil {
                        uamMinutes = (overrideArray.first?.uamMinutes ?? 30) as Decimal
                    }
                }

                let overrideTarget = (overrideArray.first?.target ?? 0) as Decimal

                var newDuration = Double(duration)
                if isEnabled {
                    let duration = overrideArray.first?.duration ?? 0
                    let addedMinutes = Int(duration as Decimal)
                    let date = overrideArray.first?.date ?? Date()
                    if date.addingTimeInterval(addedMinutes.minutes.timeInterval) < Date(), !_indefinite {
                        isEnabled = false
                    }
                    newDuration = Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes
                    if overrideTarget != 0 {
                        override_target = true
                        target = units == .mmolL ? overrideTarget.asMmolL : overrideTarget
                    }
                }

                if newDuration < 0 { newDuration = 0 } else { duration = Decimal(newDuration) }

                if !isEnabled {
                    _indefinite = true
                    percentage = 100
                    duration = 0
                    target = 0
                    override_target = false
                    smbIsOff = false
                    advancedSettings = false
                    smbMinutes = defaultSmbMinutes
                    uamMinutes = defaultUamMinutes
                }
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
            coredataContext.perform { [self] in
                let profiles = Override(context: self.coredataContext)
                profiles.enabled = false
                profiles.date = Date()
                try? self.coredataContext.save()
            }
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes
        }
    }
}

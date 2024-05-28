import CoreData
import SwiftUI

extension OverrideProfilesConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: TempTargetsStorage!
        @Injected() var apsManager: APSManager!

        @Published var percentageProfiles: Double = 100
        @Published var isEnabled = false
        @Published var _indefinite = true
        @Published var durationProfile: Decimal = 0
        @Published var target: Decimal = 0
        @Published var override_target: Bool = false
        @Published var smbIsOff: Bool = false
        @Published var id: String = ""
        @Published var profileName: String = ""
        @Published var isPreset: Bool = false
        @Published var presetsProfiles: [OverridePresets] = []
        @Published var selection: OverridePresets?
        @Published var advancedSettings: Bool = false
        @Published var isfAndCr: Bool = true
        @Published var isf: Bool = true
        @Published var cr: Bool = true
        @Published var smbIsAlwaysOff: Bool = false
        @Published var start: Decimal = 0
        @Published var end: Decimal = 23
        @Published var smbMinutes: Decimal = 0
        @Published var uamMinutes: Decimal = 0
        @Published var defaultSmbMinutes: Decimal = 0
        @Published var defaultUamMinutes: Decimal = 0
        @Published var selectedTab: Tab = .profiles

        var units: GlucoseUnits = .mmolL

        // temp target stuff
        @Published var low: Decimal = 0
        // @Published var target: Decimal = 0
        @Published var high: Decimal = 0
        @Published var durationTT: Decimal = 0
        @Published var date = Date()
        @Published var newPresetName = ""
        @Published var presetsTT: [TempTarget] = []
        @Published var percentageTT = 100.0
        @Published var maxValue: Decimal = 1.2
        @Published var viewPercantage = false
        @Published var hbt: Double = 160
        @Published var didSaveSettings: Bool = false

        override func subscribe() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            presetsProfiles = initialFetchForProfilePresets()
            presetsTT = storage.presets()
            maxValue = settingsManager.preferences.autosensMax
        }

        let coredataContext = CoreDataStack.shared.newTaskContext()

        func initialFetchForProfilePresets() -> [OverridePresets] {
            let fr = OverridePresets.fetchRequest()
            fr.predicate = NSPredicate.predicateForOneDayAgo

            var overrides: [OverridePresets] = []

            coredataContext.perform {
                do {
                    overrides = try self.coredataContext.fetch(fr)
                } catch let error as NSError {
                    print(error.localizedDescription)
                }
            }

            return overrides
        }

        func saveSettings() {
            coredataContext.perform { [self] in
                let saveOverride = Override(context: self.coredataContext)
                saveOverride.duration = self.durationProfile as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentageProfiles
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
                    if smbIsAlwaysOff {
                        saveOverride.smbIsAlwaysOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { saveOverride.smbIsAlwaysOff = false }

                    saveOverride.smbMinutes = smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = uamMinutes as NSDecimalNumber
                }
                do {
                    guard coredataContext.hasChanges else { return }
                    try coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }

        func savePreset() {
            coredataContext.perform { [self] in
                let saveOverride = OverridePresets(context: self.coredataContext)
                saveOverride.duration = self.durationProfile as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentageProfiles
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
                    if smbIsAlwaysOff {
                        saveOverride.smbIsAlwaysOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { smbIsAlwaysOff = false }

                    saveOverride.smbMinutes = smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = uamMinutes as NSDecimalNumber
                }
                do {
                    guard coredataContext.hasChanges else { return }
                    try coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
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
                    if profile.smbIsAlwaysOff {
                        saveOverride.smbIsAlwaysOff = true
                        saveOverride.start = profile.start
                        saveOverride.end = profile.end
                    } else { saveOverride.smbIsAlwaysOff = false }

                    saveOverride.smbMinutes = (profile.smbMinutes ?? 0) as NSDecimalNumber
                    saveOverride.uamMinutes = (profile.uamMinutes ?? 0) as NSDecimalNumber
                }
                do {
                    guard coredataContext.hasChanges else { return }
                    try coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
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
                percentageProfiles = overrideArray.first?.percentage ?? 100
                _indefinite = overrideArray.first?.indefinite ?? true
                durationProfile = (overrideArray.first?.duration ?? 0) as Decimal
                smbIsOff = overrideArray.first?.smbIsOff ?? false
                advancedSettings = overrideArray.first?.advancedSettings ?? false
                isfAndCr = overrideArray.first?.isfAndCr ?? true
                smbIsAlwaysOff = overrideArray.first?.smbIsAlwaysOff ?? false

                if advancedSettings {
                    if !isfAndCr {
                        isf = overrideArray.first?.isf ?? false
                        cr = overrideArray.first?.cr ?? false
                    }
                    if smbIsAlwaysOff {
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

                var newDuration = Double(durationProfile)
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

                if newDuration < 0 { newDuration = 0 } else { durationProfile = Decimal(newDuration) }

                if !isEnabled {
                    _indefinite = true
                    percentageProfiles = 100
                    durationProfile = 0
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
            percentageProfiles = 100
            durationProfile = 0
            target = 0
            override_target = false
            smbIsOff = false
            advancedSettings = false
            coredataContext.perform { [self] in
                let profiles = Override(context: self.coredataContext)
                profiles.enabled = false
                profiles.date = Date()
                do {
                    guard coredataContext.hasChanges else { return }
                    try coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            }
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes
        }

        // MARK: TEMP TARGET

        func enact() {
            guard durationTT > 0 else {
                return
            }
            var lowTarget = low

            if viewPercantage {
                lowTarget = Decimal(round(Double(computeTarget())))
                coredataContext.performAndWait {
                    let saveToCoreData = TempTargets(context: self.coredataContext)
                    saveToCoreData.id = UUID().uuidString
                    saveToCoreData.active = true
                    saveToCoreData.hbt = hbt
                    saveToCoreData.date = Date()
                    saveToCoreData.duration = durationTT as NSDecimalNumber
                    saveToCoreData.startDate = Date()
                    try? self.coredataContext.save()
                }
                didSaveSettings = true
            } else {
                coredataContext.performAndWait {
                    let saveToCoreData = TempTargets(context: coredataContext)
                    saveToCoreData.active = false
                    saveToCoreData.date = Date()
                    do {
                        guard coredataContext.hasChanges else { return }
                        try coredataContext.save()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
            var highTarget = lowTarget

            if units == .mmolL, !viewPercantage {
                lowTarget = Decimal(round(Double(lowTarget.asMgdL)))
                highTarget = lowTarget
            }

            let entry = TempTarget(
                name: TempTarget.custom,
                createdAt: date,
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: durationTT,
                enteredBy: TempTarget.manual,
                reason: TempTarget.custom
            )
            storage.storeTempTargets([entry])
            showModal(for: nil)
        }

        func cancel() {
            storage.storeTempTargets([TempTarget.cancel(at: Date())])
            showModal(for: nil)

            coredataContext.performAndWait {
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.active = false
                saveToCoreData.date = Date()
                do {
                    guard coredataContext.hasChanges else { return }
                    try coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }

                let setHBT = TempTargetsSlider(context: self.coredataContext)
                setHBT.enabled = false
                setHBT.date = Date()
                do {
                    guard coredataContext.hasChanges else { return }
                    try coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }

        func save() {
            guard durationTT > 0 else {
                return
            }
            var lowTarget = low

            if viewPercantage {
                lowTarget = Decimal(round(Double(computeTarget())))
                didSaveSettings = true
            }
            var highTarget = lowTarget

            if units == .mmolL, !viewPercantage {
                lowTarget = Decimal(round(Double(lowTarget.asMgdL)))
                highTarget = lowTarget
            }

            let entry = TempTarget(
                name: newPresetName.isEmpty ? TempTarget.custom : newPresetName,
                createdAt: Date(),
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: durationTT,
                enteredBy: TempTarget.manual,
                reason: newPresetName.isEmpty ? TempTarget.custom : newPresetName
            )
            presetsTT.append(entry)
            storage.storePresets(presetsTT)

            if viewPercantage {
                let id = entry.id

                coredataContext.performAndWait {
                    let saveToCoreData = TempTargetsSlider(context: self.coredataContext)
                    saveToCoreData.id = id
                    saveToCoreData.isPreset = true
                    saveToCoreData.enabled = true
                    saveToCoreData.hbt = hbt
                    saveToCoreData.date = Date()
                    saveToCoreData.duration = durationTT as NSDecimalNumber
                    do {
                        guard coredataContext.hasChanges else { return }
                        try coredataContext.save()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
        }

        func enactPreset(id: String) {
            if var preset = presetsTT.first(where: { $0.id == id }) {
                preset.createdAt = Date()
                storage.storeTempTargets([preset])
                showModal(for: nil)

                coredataContext.performAndWait {
                    var tempTargetsArray = [TempTargetsSlider]()
                    let requestTempTargets = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
                    let sortTT = NSSortDescriptor(key: "date", ascending: false)
                    requestTempTargets.sortDescriptors = [sortTT]
                    try? tempTargetsArray = coredataContext.fetch(requestTempTargets)

                    let whichID = tempTargetsArray.first(where: { $0.id == id })

                    if whichID != nil {
                        let saveToCoreData = TempTargets(context: self.coredataContext)
                        saveToCoreData.active = true
                        saveToCoreData.date = Date()
                        saveToCoreData.hbt = whichID?.hbt ?? 160
                        // saveToCoreData.id = id
                        saveToCoreData.startDate = Date()
                        saveToCoreData.duration = whichID?.duration ?? 0

                        do {
                            guard coredataContext.hasChanges else { return }
                            try coredataContext.save()
                        } catch {
                            print(error.localizedDescription)
                        }
                    } else {
                        let saveToCoreData = TempTargets(context: self.coredataContext)
                        saveToCoreData.active = false
                        saveToCoreData.date = Date()
                        do {
                            guard coredataContext.hasChanges else { return }
                            try coredataContext.save()
                        } catch {
                            print(error.localizedDescription)
                        }
                    }
                }
            }
        }

        func removePreset(id: String) {
            presetsTT = presetsTT.filter { $0.id != id }
            storage.storePresets(presetsTT)
        }

        func computeTarget() -> Decimal {
            var ratio = Decimal(percentageTT / 100)
            let c = Decimal(hbt - 100)
            var target = (c / ratio) - c + 100

            if c * (c + target - 100) <= 0 {
                ratio = maxValue
                target = (c / ratio) - c + 100
            }
            return Decimal(Double(target))
        }
    }
}

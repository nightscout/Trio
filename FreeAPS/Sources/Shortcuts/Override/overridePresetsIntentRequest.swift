import CoreData
import Foundation

@available(iOS 16.0, *) final class OverridePresetsIntentRequest: BaseIntentsRequest {
    enum overridePresetsError: Error {
        case noTempOverrideFound
        case noDurationDefined
    }

    var overrideList: [OverridePresets] {
        var profileArray = [OverridePresets]()
        let requestProfiles = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
        try? profileArray = coredataContext.fetch(requestProfiles)
        return profileArray
    }

    func fetchAll() -> [overridePreset] {
        overrideList.compactMap { override in
            guard let id = override.id, let name = override.name else { return nil }
            return overridePreset(id: id, name: name)
        }
        // convert(tt: tempTargetsStorage.presets())
    }

    func fetchIDs(_ uuid: [overridePreset.ID]) -> [overridePreset] {
        let UUIDTempTarget = overrideList.filter {
            guard let id = $0.id else { return false }
            return uuid.contains(id) }

        return UUIDTempTarget.compactMap { override in
            guard let id = override.id, let name = override.name else { return nil }
            return overridePreset(id: id, name: name)
        }
    }

    func fetchOne(_ uuid: overridePreset.ID) -> overridePreset? {
        let UUIDTempTarget = overrideList.filter { uuid == $0.id! }
        guard let OneTempTarget = UUIDTempTarget.first,
              let id = OneTempTarget.id,
              let name = OneTempTarget.name
        else { return nil }

        return overridePreset(id: id, name: name)
    }

    func enactTempOverride(_ presetTarget: overridePreset) throws -> Bool {
        let id_ = presetTarget.id
        coredataContext.performAndWait {
            guard let profile = overrideList.filter({ $0.id == id_ }).first else { return }

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
                if !profile.isfAndCr {
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
            try? self.coredataContext.save()
        }
        return true
    }

    func cancelTempTarget() throws {
        coredataContext.perform { [self] in
            let profiles = Override(context: self.coredataContext)
            profiles.enabled = false
            profiles.date = Date()
            try? self.coredataContext.save()
        }
    }
}

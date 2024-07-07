import CoreData
import Foundation

@available(iOS 16.0, *) final class OverridePresetsIntentRequest: BaseIntentsRequest {
    enum overridePresetsError: Error {
        case noTempOverrideFound
        case noDurationDefined
        case noActiveOverride
    }

    var overrideList: [OverridePresets] {
        var profileArray = [OverridePresets]()
        let requestProfiles = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
        try? profileArray = coredataContext.fetch(requestProfiles)
        return profileArray
    }

    func fetchAll() -> [OverridePreset] {
        overrideList.compactMap { override in
            guard let id = override.id, let name = override.name else { return nil }
            return OverridePreset(id: id, name: name)
        }
        // convert(tt: tempTargetsStorage.presets())
    }

    func fetchIDs(_ uuid: [OverridePreset.ID]) -> [OverridePreset] {
        let UUIDTempTarget = overrideList.filter {
            guard let id = $0.id else { return false }
            return uuid.contains(id) }

        return UUIDTempTarget.compactMap { override in
            guard let id = override.id, let name = override.name else { return nil }
            return OverridePreset(id: id, name: name)
        }
    }

    func fetchOne(_ uuid: OverridePreset.ID) -> OverridePreset? {
        let UUIDTempTarget = overrideList.filter { uuid == $0.id }
        guard let OneTempTarget = UUIDTempTarget.first
        else { return nil }
        guard let id = OneTempTarget.id,
              let name = OneTempTarget.name
        else { return nil }

        return OverridePreset(id: id, name: name)
    }

    func enactTempOverride(_ presetTarget: OverridePreset) throws -> Bool {
        let id = presetTarget.id
        coredataContext.performAndWait {
            guard let profile = overrideList.filter({ $0.id == id }).first else { return }

            let saveOverride = Override(context: self.coredataContext)
            saveOverride.duration = (profile.duration ?? 0) as NSDecimalNumber
            saveOverride.indefinite = profile.indefinite
            saveOverride.percentage = profile.percentage
            saveOverride.enabled = true
            saveOverride.smbIsOff = profile.smbIsOff
            saveOverride.isPreset = true
            saveOverride.date = Date()
            saveOverride.target = profile.target
            saveOverride.id = id

            if profile.advancedSettings {
                saveOverride.advancedSettings = true
                if !profile.isfAndCr {
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
        return true
    }

    func cancelOverride() throws -> String? {
        var cancelledOverrideName: String?
        try? coredataContext.perform { [self] in
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            requestOverrides.predicate = NSPredicate(format: "enabled == %@", NSNumber(value: true))
            if let activeOverride = try? self.coredataContext.fetch(requestOverrides).last {
                if let activeOverrideId = activeOverride.id, let fetchedOverride = fetchOne(activeOverrideId) {
                    cancelledOverrideName = fetchedOverride.name
                }
                activeOverride.enabled = false
                activeOverride.date = Date()
                try? self.coredataContext.save()
            } else {
                throw overridePresetsError.noActiveOverride
            }
        }
        return cancelledOverrideName
    }
}

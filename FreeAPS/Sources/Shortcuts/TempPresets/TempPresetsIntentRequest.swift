import CoreData
import Foundation

@available(iOS 16.0, *) final class TempPresetsIntentRequest: BaseIntentsRequest {
    enum TempPresetsError: Error {
        case noTempTargetFound
        case noDurationDefined
    }

    private func convert(tt: [TempTarget]) -> [tempPreset] {
        tt.map { tempPreset.convert($0) }
    }

    func fetchAll() -> [tempPreset] {
        convert(tt: tempTargetsStorage.presets())
    }

    func fetchIDs(_ uuid: [tempPreset.ID]) -> [tempPreset] {
        let UUIDTempTarget = tempTargetsStorage.presets().filter { uuid.contains(UUID(uuidString: $0.id)!) }
        return convert(tt: UUIDTempTarget)
    }

    func fetchOne(_ uuid: tempPreset.ID) -> tempPreset? {
        let UUIDTempTarget = tempTargetsStorage.presets().filter { UUID(uuidString: $0.id) == uuid }
        guard let OneTempTarget = UUIDTempTarget.first else { return nil }
        return tempPreset.convert(OneTempTarget)
    }

    func findTempTarget(_ tempPreset: tempPreset) throws -> TempTarget {
        let tempTargetFound = tempTargetsStorage.presets().filter { $0.id == tempPreset.id.uuidString }
        guard let tempOneTarget = tempTargetFound.first else { throw TempPresetsError.noTempTargetFound }
        return tempOneTarget
    }

    func enactTempTarget(_ presetTarget: TempTarget) throws -> TempTarget {
        var tempTarget = presetTarget
        tempTarget.createdAt = Date()
        storage.storeTempTargets([tempTarget])

        coredataContext.performAndWait {
            var tempTargetsArray = [TempTargetsSlider]()
            let requestTempTargets = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            try? tempTargetsArray = coredataContext.fetch(requestTempTargets)

            let whichID = tempTargetsArray.first(where: { $0.id == tempTarget.id })

            if whichID != nil {
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.active = true
                saveToCoreData.date = Date()
                saveToCoreData.hbt = whichID?.hbt ?? 160
                saveToCoreData.startDate = Date()
                saveToCoreData.duration = whichID?.duration ?? 0

                try? self.coredataContext.save()
            } else {
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.active = false
                saveToCoreData.date = Date()
                try? self.coredataContext.save()
            }
        }

        return tempTarget
    }

    func cancelTempTarget() throws {
        storage.storeTempTargets([TempTarget.cancel(at: Date())])
        try coredataContext.performAndWait {
            let saveToCoreData = TempTargets(context: self.coredataContext)
            saveToCoreData.active = false
            saveToCoreData.date = Date()
            try self.coredataContext.save()

            let setHBT = TempTargetsSlider(context: self.coredataContext)
            setHBT.enabled = false
            setHBT.date = Date()

            try self.coredataContext.save()
        }
    }

    /// function to enact a new temp target from date, target and duration information
    func enactTempTarget(date: Date, target: Decimal, unit: UnitList?, duration: Decimal) throws -> TempTarget? {
        // check the unit or take the settings unit
        var glucoseUnit: GlucoseUnits
        if let unit = unit {
            switch unit {
            case .mgdL:
                glucoseUnit = .mgdL
            case .mmolL:
                glucoseUnit = .mmolL
            }
        } else {
            glucoseUnit = settingsManager.settings.units
        }

        // convert target if required the unit in regard of the settings unit
        var targetCorrectUnit: Decimal = target
        if glucoseUnit != settingsManager.settings.units {
            targetCorrectUnit = (settingsManager.settings.units == .mgdL) ? target.asMgdL : target.asMmolL
        }

        coredataContext.performAndWait {
            let saveToCoreData = TempTargets(context: coredataContext)
            saveToCoreData.active = false
            saveToCoreData.date = Date()
            try? coredataContext.save()
        }

        let entry = TempTarget(
            name: TempTarget.custom,
            createdAt: date,
            targetTop: targetCorrectUnit,
            targetBottom: targetCorrectUnit,
            duration: duration,
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom
        )
        storage.storeTempTargets([entry])
        return entry
    }
}

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

    // TODO: - probably broken for now...

    func enactTempTarget(_ presetTarget: TempTarget) async throws -> TempTarget {
        var tempTarget = presetTarget
        tempTarget.createdAt = Date()
        await storage.storeTempTarget(tempTarget: tempTarget)

        coredataContext.performAndWait {
            var tempTargetsArray = [TempTargetStored]()
            let requestTempTargets = TempTargetStored.fetchRequest() as NSFetchRequest<TempTargetStored>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            if coredataContext.hasChanges {
                try? tempTargetsArray = coredataContext.fetch(requestTempTargets)
            }

            let whichID = tempTargetsArray.first(where: { $0.id == UUID(uuidString: tempTarget.id) })

            if whichID != nil {
                let saveToCoreData = TempTargetStored(context: self.coredataContext)
                saveToCoreData.enabled = true
                saveToCoreData.date = Date()
                saveToCoreData.target = whichID?.target ?? 160
                saveToCoreData.date = Date()
                saveToCoreData.duration = whichID?.duration ?? 0

                do {
                    guard coredataContext.hasChanges else { return }
                    try self.coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            } else {
                let saveToCoreData = TempTargetStored(context: self.coredataContext)
                saveToCoreData.enabled = false
                saveToCoreData.date = Date()
                do {
                    guard coredataContext.hasChanges else { return }
                    try self.coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }

        return tempTarget
    }

    func cancelTempTarget() async throws {
        await storage.storeTempTarget(tempTarget: TempTarget.cancel(at: Date()))
        try coredataContext.performAndWait {
            let saveToCoreData = TempTargetStored(context: self.coredataContext)
            saveToCoreData.enabled = false
            saveToCoreData.date = Date()
            if coredataContext.hasChanges {
                try self.coredataContext.save()
            }

            let setHBT = TempTargetStored(context: self.coredataContext)
            setHBT.enabled = false
            setHBT.date = Date()
            if coredataContext.hasChanges {
                try self.coredataContext.save()
            }
        }
    }
}

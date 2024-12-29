import CoreData
import Foundation

extension TrioRemoteControl {
    @MainActor internal func handleCancelOverrideCommand(_ pushMessage: PushMessage) async {
        await disableAllActiveOverrides()

        debug(
            .remoteControl,
            "Remote command processed successfully. \(pushMessage.humanReadableDescription())"
        )
    }

    @MainActor internal func handleStartOverrideCommand(_ pushMessage: PushMessage) async {
        guard let overrideName = pushMessage.overrideName, !overrideName.isEmpty else {
            await logError("Command rejected: override name is missing.", pushMessage: pushMessage)
            return
        }

        let presetIDs = await overrideStorage.fetchForOverridePresets()

        let presets = presetIDs.compactMap { id in
            try? viewContext.existingObject(with: id) as? OverrideStored
        }

        if let preset = presets.first(where: { $0.name == overrideName }) {
            await enactOverridePreset(preset: preset, pushMessage: pushMessage)
        } else {
            await logError("Command rejected: override preset '\(overrideName)' not found.", pushMessage: pushMessage)
        }
    }

    @MainActor private func enactOverridePreset(preset: OverrideStored, pushMessage: PushMessage) async {
        preset.enabled = true
        preset.date = Date()
        preset.isUploadedToNS = false

        await disableAllActiveOverrides(except: preset.objectID)

        do {
            if viewContext.hasChanges {
                try viewContext.save()

                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                await awaitNotification(.didUpdateOverrideConfiguration)

                debug(.remoteControl, "Remote command processed successfully. \(pushMessage.humanReadableDescription())")
            }
        } catch {
            debug(.remoteControl, "Failed to enact override preset: \(error.localizedDescription)")
        }
    }

    @MainActor private func disableAllActiveOverrides(except overrideID: NSManagedObjectID? = nil) async {
        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0) // 0 = no fetch limit

        let didPostNotification = await viewContext.perform { () -> Bool in
            do {
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? OverrideStored
                }

                guard !results.isEmpty else { return false }

                for canceledOverride in results where canceledOverride.enabled {
                    if let overrideID = overrideID, canceledOverride.objectID == overrideID {
                        continue
                    }

                    let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                    newOverrideRunStored.id = UUID()
                    newOverrideRunStored.name = canceledOverride.name
                    newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                    newOverrideRunStored.endDate = Date()
                    newOverrideRunStored.target = NSDecimalNumber(
                        decimal: self.overrideStorage.calculateTarget(override: canceledOverride)
                    )
                    newOverrideRunStored.override = canceledOverride
                    newOverrideRunStored.isUploadedToNS = false

                    canceledOverride.enabled = false
                    canceledOverride.isUploadedToNS = false
                }

                if self.viewContext.hasChanges {
                    try self.viewContext.save()
                    Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                    return true
                } else {
                    return false
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Overrides with error: \(error.localizedDescription)"
                )
                return false
            }
        }

        if didPostNotification {
            await awaitNotification(.didUpdateOverrideConfiguration)
        }
    }
}

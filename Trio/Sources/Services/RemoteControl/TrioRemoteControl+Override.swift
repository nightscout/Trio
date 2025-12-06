import CoreData
import Foundation
import UIKit

extension TrioRemoteControl {
    @MainActor internal func handleCancelOverrideCommand(_ payload: CommandPayload) async {
        await disableAllActiveOverrides()
        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: "Override canceled"
        )
    }

    @MainActor internal func handleStartOverrideCommand(_ payload: CommandPayload) async {
        do {
            guard let overrideName = payload.overrideName, !overrideName.isEmpty else {
                await logError("Command rejected: override name is missing.", payload: payload)
                return
            }
            let presetIDs = try await overrideStorage.fetchForOverridePresets()
            let presets = try presetIDs.compactMap { try viewContext.existingObject(with: $0) as? OverrideStored }
            if let preset = presets.first(where: { $0.name == overrideName }) {
                await enactOverridePreset(preset: preset, payload: payload)
            } else {
                await logError("Command rejected: override preset '\(overrideName)' not found.", payload: payload)
            }
        } catch {
            debug(.remoteControl, "\(DebuggingIdentifiers.failed) Failed to handle start override command: \(error)")
            await logError("Command failed: \(error.localizedDescription)", payload: payload)
        }
    }

    @MainActor private func enactOverridePreset(preset: OverrideStored, payload: CommandPayload) async {
        preset.enabled = true
        preset.date = Date()
        preset.isUploadedToNS = false
        await disableAllActiveOverrides(except: preset.objectID)
        do {
            if viewContext.hasChanges {
                try viewContext.save()
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                await awaitNotification(.didUpdateOverrideConfiguration)
                await logSuccess(
                    "Remote command processed successfully. \(payload.humanReadableDescription())",
                    payload: payload,
                    customNotificationMessage: "Override started"
                )
            }
        } catch {
            debug(.remoteControl, "Failed to enact override preset: \(error)")
            await logError("Failed to enact override preset: \(error.localizedDescription)", payload: payload)
        }
    }

    @MainActor private func disableAllActiveOverrides(except overrideID: NSManagedObjectID? = nil) async {
        do {
            let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)
            let didPostNotification = try await viewContext.perform { () -> Bool in
                let results = try ids.compactMap { try self.viewContext.existingObject(with: $0) as? OverrideStored }
                guard !results.isEmpty else { return false }
                for canceledOverride in results where canceledOverride.enabled {
                    if let overrideID = overrideID, canceledOverride.objectID == overrideID { continue }
                    let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                    newOverrideRunStored.id = UUID()
                    newOverrideRunStored.name = canceledOverride.name
                    newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                    newOverrideRunStored.endDate = Date()
                    newOverrideRunStored
                        .target = NSDecimalNumber(decimal: self.overrideStorage.calculateTarget(override: canceledOverride))
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
            }
            if didPostNotification { await awaitNotification(.didUpdateOverrideConfiguration) }
        } catch {
            debug(.remoteControl, "\(DebuggingIdentifiers.failed) Failed to disable active overrides: \(error)")
        }
    }
}

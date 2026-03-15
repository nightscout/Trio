import CoreData
import Foundation
import UIKit

extension TrioRemoteControl {
    @MainActor func handleTempTargetCommand(_ payload: CommandPayload) async throws {
        guard let targetValue = payload.target, let durationValue = payload.duration else {
            await logError("Command rejected: temp target data is incomplete or invalid.", payload: payload)
            return
        }

        let durationInMinutes = Int(durationValue)
        let payloadDate = Date(timeIntervalSince1970: payload.timestamp)

        let tempTarget = TempTarget(
            name: TempTarget.custom, createdAt: payloadDate,
            targetTop: Decimal(targetValue), targetBottom: Decimal(targetValue),
            duration: Decimal(durationInMinutes), enteredBy: TempTarget.local,
            reason: TempTarget.custom, isPreset: false, enabled: true,
            halfBasalTarget: settings.preferences.halfBasalExerciseTarget
        )

        try await tempTargetsStorage.storeTempTarget(tempTarget: tempTarget)
        tempTargetsStorage.saveTempTargetsToStorage([tempTarget])

        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: "Temp target set"
        )
    }

    @MainActor func cancelTempTarget(_ payload: CommandPayload) async {
        debug(.remoteControl, "Cancelling temp target.")
        await disableAllActiveTempTargets()
        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: "Temp target canceled"
        )
    }

    @MainActor func disableAllActiveTempTargets() async {
        do {
            let ids = try await tempTargetsStorage.loadLatestTempTargetConfigurations(fetchLimit: 0)
            let didPostNotification = try await viewContext.perform { () -> Bool in
                let results = try ids.compactMap { try self.viewContext.existingObject(with: $0) as? TempTargetStored }
                guard !results.isEmpty else {
                    Task { await self.logError("Command rejected: no active temp target to cancel.") }
                    return false
                }
                for canceledTempTarget in results where canceledTempTarget.enabled {
                    let newTempTargetRunStored = TempTargetRunStored(context: self.viewContext)
                    newTempTargetRunStored.id = UUID()
                    newTempTargetRunStored.name = canceledTempTarget.name
                    newTempTargetRunStored.startDate = canceledTempTarget.date ?? .distantPast
                    newTempTargetRunStored.endDate = Date()
                    newTempTargetRunStored.target = canceledTempTarget.target ?? 0
                    newTempTargetRunStored.tempTarget = canceledTempTarget
                    newTempTargetRunStored.isUploadedToNS = false
                    canceledTempTarget.enabled = false
                    canceledTempTarget.isUploadedToNS = false
                }
                if self.viewContext.hasChanges {
                    try self.viewContext.save()
                    Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)
                    self.tempTargetsStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date().addingTimeInterval(-1))])
                    return true
                } else {
                    return false
                }
            }
            if didPostNotification { await awaitNotification(.didUpdateTempTargetConfiguration) }
        } catch {
            debug(.remoteControl, "\(DebuggingIdentifiers.failed) Failed to disable active temp targets: \(error)")
            await logError("Failed to disable temp targets: \(error.localizedDescription)")
        }
    }
}

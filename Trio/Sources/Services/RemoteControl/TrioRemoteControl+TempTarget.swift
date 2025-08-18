import CoreData
import Foundation

extension TrioRemoteControl {
    @MainActor func handleTempTargetCommand(_ pushMessage: PushMessage) async throws {
        guard let targetValue = pushMessage.target,
              let durationValue = pushMessage.duration
        else {
            await logError("Command rejected: temp target data is incomplete or invalid.", pushMessage: pushMessage)
            return
        }

        let durationInMinutes = Int(durationValue)
        let pushMessageDate = Date(timeIntervalSince1970: pushMessage.timestamp)

        let tempTarget = TempTarget(
            name: TempTarget.custom,
            createdAt: pushMessageDate,
            targetTop: Decimal(targetValue),
            targetBottom: Decimal(targetValue),
            duration: Decimal(durationInMinutes),
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: true,
            halfBasalTarget: settings.preferences.halfBasalExerciseTarget
        )

        try await tempTargetsStorage.storeTempTarget(tempTarget: tempTarget)
        tempTargetsStorage.saveTempTargetsToStorage([tempTarget])

        debug(
            .remoteControl,
            "Remote command processed successfully. \(pushMessage.humanReadableDescription())"
        )
    }

    @MainActor func cancelTempTarget(_ pushMessage: PushMessage) async {
        debug(.remoteControl, "Cancelling temp target.")

        await disableAllActiveTempTargets()

        debug(
            .remoteControl,
            "Remote command processed successfully. \(pushMessage.humanReadableDescription())"
        )
    }

    @MainActor func disableAllActiveTempTargets() async {
        do {
            let ids = try await tempTargetsStorage.loadLatestTempTargetConfigurations(fetchLimit: 0)

            let didPostNotification = try await viewContext.perform { () -> Bool in
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? TempTargetStored
                }

                guard !results.isEmpty else {
                    Task {
                        await self.logError("Command rejected: no active temp target to cancel.")
                    }
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

                    // Update the storage so oref can pick up cancellation
                    self.tempTargetsStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date().addingTimeInterval(-1))])
                    return true
                } else {
                    return false
                }
            }

            if didPostNotification {
                await awaitNotification(.didUpdateTempTargetConfiguration)
            }
        } catch {
            debug(
                .remoteControl,
                "\(DebuggingIdentifiers.failed) Failed to disable active temp targets: \(error)"
            )
            await logError("Failed to disable temp targets: \(error.localizedDescription)")
        }
    }
}

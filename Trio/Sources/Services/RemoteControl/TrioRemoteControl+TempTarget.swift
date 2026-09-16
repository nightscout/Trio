import CoreData
import Foundation

extension TrioRemoteControl {
    @MainActor func handleTempTargetCommand(_ payload: CommandPayload) async throws {
        guard let targetValue = payload.target, let durationValue = payload.duration else {
            await logError("Command rejected: temp target data is incomplete or invalid.", payload: payload)
            return
        }

        // Stored disabled and then activated through the manager, which ends and records whatever
        // was running, stamps the start, and hands oref the new entry.
        let tempTarget = TempTarget(
            name: TempTarget.custom, createdAt: Date(),
            targetTop: Decimal(targetValue), targetBottom: Decimal(targetValue),
            duration: Decimal(Int(durationValue)), enteredBy: TempTarget.local,
            reason: TempTarget.custom, isPreset: false, enabled: false,
            halfBasalTarget: settings.preferences.halfBasalExerciseTarget
        )

        do {
            let objectID = try await tempTargetsStorage.storeTempTarget(tempTarget: tempTarget)
            let outcome = try await adjustmentManager.activateTempTarget(
                .objectID(objectID),
                source: .remote,
                waitForUpload: true
            )
            if let ended = outcome.ended.first {
                debug(.remoteControl, "Recorded run for replaced temp target \"\(ended.name ?? "Temp Target")\"")
            }
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Temp target set"
            )
        } catch let error as AdjustmentError {
            await logError("Command rejected: \(error.errorDescription ?? "unknown reason")", payload: payload)
        } catch {
            await logError("Command failed: \(error.localizedDescription)", payload: payload)
        }
    }

    @MainActor func cancelTempTarget(_ payload: CommandPayload) async {
        do {
            let outcome = try await adjustmentManager.cancelTempTarget(source: .remote, waitForUpload: true)
            debug(.remoteControl, "Cancelled temp target \"\(outcome.ended.first?.name ?? "Temp Target")\"")
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Temp target canceled"
            )
        } catch AdjustmentError.nothingActive {
            // Nothing was running, which is the state the command asked for.
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Temp target canceled"
            )
        } catch {
            debug(.remoteControl, "Failed to cancel temp target: \(error)")
            await logError("Command failed: \(error.localizedDescription)", payload: payload)
        }
    }
}

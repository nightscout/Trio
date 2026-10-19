import Foundation

extension TrioRemoteControl {
    @MainActor func handleCancelOverrideCommand(_ payload: CommandPayload) async {
        do {
            let outcome = try await adjustmentManager.cancelOverride(source: .remote, waitForUpload: true)
            debug(.remote, "Override \"\(outcome.ended.first?.name ?? "Custom Override")\" cancelled")
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Override canceled"
            )
        } catch AdjustmentError.nothingActive {
            // Nothing was running, which is the state the command asked for.
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Override canceled"
            )
        } catch {
            warning(.remote, "Override cancel failed", error: error)
            await logError("Command failed: \(error.localizedDescription)", payload: payload)
        }
    }

    @MainActor func handleStartOverrideCommand(_ payload: CommandPayload) async {
        guard let overrideName = payload.overrideName, !overrideName.isEmpty else {
            await logError("Command rejected: override name is missing.", payload: payload)
            return
        }

        do {
            let outcome = try await adjustmentManager.activateOverride(
                .presetName(overrideName),
                source: .remote,
                waitForUpload: true
            )
            if let ended = outcome.ended.first {
                debug(.remote, "Recorded run for replaced override \"\(ended.name ?? "Custom Override")\"")
            }
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Override started"
            )
        } catch let error as AdjustmentError {
            await logError("Command rejected: \(error.errorDescription ?? "unknown reason")", payload: payload)
        } catch {
            await logError("Command failed: \(error.localizedDescription)", payload: payload)
        }
    }
}

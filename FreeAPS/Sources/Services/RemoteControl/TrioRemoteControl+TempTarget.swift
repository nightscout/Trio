import Foundation

extension TrioRemoteControl {
    func handleTempTargetCommand(_ pushMessage: PushMessage) async {
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
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: true,
            halfBasalTarget: settings.preferences.halfBasalExerciseTarget
        )

        // TODO: this should probably be try-catch'd ?
        await tempTargetsStorage.storeTempTarget(tempTarget: tempTarget)

        debug(
            .remoteControl,
            "Remote command processed successfully. \(pushMessage.humanReadableDescription())"
        )
    }

    func cancelTempTarget(_ pushMessage: PushMessage) async {
        debug(.remoteControl, "Cancelling temp target.")

        guard tempTargetsStorage.current() != nil else {
            await logError("Command rejected: no active temp target to cancel.")
            return
        }

        let cancelEntry = TempTarget.cancel(at: Date())
        await tempTargetsStorage.storeTempTarget(tempTarget: cancelEntry)

        debug(
            .remoteControl,
            "Remote command processed successfully. \(pushMessage.humanReadableDescription())"
        )
    }
}

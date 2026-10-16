import Foundation

extension TrioRemoteControl {
    func logError(_ errorMessage: String, payload: CommandPayload? = nil, ack: RemoteCommandAck? = nil) async {
        var note = errorMessage
        if let payload = payload {
            note += " Details: \(payload.humanReadableDescription())"

            if let returnInfo = payload.returnNotification {
                await RemoteNotificationResponseManager.shared.sendResponseNotification(
                    to: returnInfo,
                    commandType: payload.commandType,
                    success: false,
                    message: errorMessage,
                    ack: ack
                )
            }
        }
        debug(.remoteControl, note)
        await nightscoutManager.uploadNoteTreatment(note: note)
    }

    func logSuccess(
        _ message: String,
        payload: CommandPayload,
        customNotificationMessage: String? = nil,
        ack: RemoteCommandAck? = nil
    ) async {
        debug(.remoteControl, message)

        if let returnInfo = payload.returnNotification {
            await RemoteNotificationResponseManager.shared.sendResponseNotification(
                to: returnInfo,
                commandType: payload.commandType,
                success: true,
                message: customNotificationMessage ?? "Command successful",
                ack: ack
            )
        }
    }
}

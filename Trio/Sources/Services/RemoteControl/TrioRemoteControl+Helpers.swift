import Foundation

extension TrioRemoteControl {
    func logError(_ errorMessage: String, payload: CommandPayload? = nil) async {
        var note = errorMessage
        if let payload = payload {
            note += " Details: \(payload.humanReadableDescription())"

            if let returnInfo = payload.returnNotification {
                await RemoteNotificationResponseManager.shared.sendResponseNotification(
                    to: returnInfo,
                    commandType: payload.commandType,
                    success: false,
                    message: errorMessage
                )
            }
        }
        debug(.remoteControl, note)
        await nightscoutManager.uploadNoteTreatment(note: note)
    }

    func logSuccess(_ message: String, payload: CommandPayload, customNotificationMessage: String? = nil) async {
        debug(.remoteControl, message)

        if let returnInfo = payload.returnNotification {
            await RemoteNotificationResponseManager.shared.sendResponseNotification(
                to: returnInfo,
                commandType: payload.commandType,
                success: true,
                message: customNotificationMessage ?? "Command successful"
            )
        }
    }
}

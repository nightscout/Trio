import Foundation

class RemoteNotificationResponseManager {
    static let shared = RemoteNotificationResponseManager()

    private init() {}

    struct NotificationPayload: Encodable {
        let aps: APSPayload
        let commandStatus: String
        let commandType: String
        let timestamp: TimeInterval

        enum CodingKeys: String, CodingKey {
            case aps
            case commandStatus = "command_status"
            case commandType = "command_type"
            case timestamp
        }
    }

    struct APSPayload: Encodable {
        let alert: Alert
        let sound: String = "default"
    }

    struct Alert: Encodable {
        let title: String
        let body: String
    }

    func sendResponseNotification(
        to returnInfo: CommandPayload.ReturnNotificationInfo?,
        commandType: TrioRemoteControl.CommandType,
        success: Bool,
        message: String
    ) async {
        guard let returnInfo = returnInfo,
              !returnInfo.deviceToken.isEmpty
        else {
            debug(.remoteControl, "No return notification info provided, skipping response")
            return
        }

        let payload = NotificationPayload(
            aps: APSPayload(
                alert: Alert(
                    title: success ? "Command Successful" : "Command Failed",
                    body: message
                )
            ),
            commandStatus: success ? "success" : "failed",
            commandType: commandType.rawValue,
            timestamp: Date().timeIntervalSince1970
        )

        await sendPushNotification(
            payload: payload,
            to: returnInfo.deviceToken,
            using: returnInfo
        )
    }

    private func sendPushNotification(
        payload: NotificationPayload,
        to deviceToken: String,
        using returnInfo: CommandPayload.ReturnNotificationInfo
    ) async {
        guard let jwt = APNSJWTManager.shared.getOrGenerateJWT(
            keyId: returnInfo.keyId,
            teamId: returnInfo.teamId,
            apnsKey: returnInfo.apnsKey
        ) else {
            debug(.remoteControl, "Failed to generate JWT for response notification")
            return
        }

        let host = returnInfo.productionEnvironment ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(deviceToken)") else {
            debug(.remoteControl, "Failed to construct APNs URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("0", forHTTPHeaderField: "apns-expiration")
        request.setValue(returnInfo.bundleId, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")

        do {
            let jsonData = try JSONEncoder().encode(payload)
            request.httpBody = jsonData

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    debug(.remoteControl, "Response notification sent successfully")
                } else {
                    debug(.remoteControl, "Failed to send response notification: \(httpResponse.statusCode)")
                }
            }
        } catch {
            debug(.remoteControl, "Error sending response notification: \(error.localizedDescription)")
        }
    }
}

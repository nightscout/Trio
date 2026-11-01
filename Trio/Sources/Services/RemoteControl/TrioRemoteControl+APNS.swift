import Foundation

extension TrioRemoteControl {
    internal func handleAPNSChanges(deviceToken: String?) async throws {
        let previousDeviceToken = UserDefaults.standard.string(forKey: "deviceToken")
        let previousIsAPNSProduction = UserDefaults.standard.bool(forKey: "isAPNSProduction")

        let isAPNSProduction = isRunningInAPNSProductionEnvironment()
        var shouldUploadProfiles = false

        if let token = deviceToken, token != previousDeviceToken {
            UserDefaults.standard.set(token, forKey: "deviceToken")
            info(.remote, "Push device token updated")
            shouldUploadProfiles = true
        }

        if previousIsAPNSProduction != isAPNSProduction {
            UserDefaults.standard.set(isAPNSProduction, forKey: "isAPNSProduction")
            info(.remote, "Push environment changed to \(isAPNSProduction ? "production" : "sandbox")")
            shouldUploadProfiles = true
        }

        if shouldUploadProfiles {
            try await nightscoutManager.uploadProfiles()
        } else {
            debug(.remote, "Push device token and environment unchanged")
        }
    }

    private func isRunningInAPNSProductionEnvironment() -> Bool {
        BuildDetails.shared.isTestFlightBuild()
    }
}

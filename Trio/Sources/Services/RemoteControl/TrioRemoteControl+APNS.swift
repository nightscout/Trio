//
// Trio
// TrioRemoteControl+APNS.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-05-24.
// Most contributions by Jonas Björkert and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import Foundation

extension TrioRemoteControl {
    func handleAPNSChanges(deviceToken: String?) async throws {
        let previousDeviceToken = UserDefaults.standard.string(forKey: "deviceToken")
        let previousIsAPNSProduction = UserDefaults.standard.bool(forKey: "isAPNSProduction")

        let isAPNSProduction = isRunningInAPNSProductionEnvironment()
        var shouldUploadProfiles = false

        if let token = deviceToken, token != previousDeviceToken {
            UserDefaults.standard.set(token, forKey: "deviceToken")
            debug(.remoteControl, "Device token updated: \(token)")
            shouldUploadProfiles = true
        }

        if previousIsAPNSProduction != isAPNSProduction {
            UserDefaults.standard.set(isAPNSProduction, forKey: "isAPNSProduction")
            debug(.remoteControl, "APNS environment changed to: \(isAPNSProduction ? "Production" : "Sandbox")")
            shouldUploadProfiles = true
        }

        if shouldUploadProfiles {
            try await nightscoutManager.uploadProfiles()
        } else {
            debug(.remoteControl, "No changes detected in device token or APNS environment.")
        }
    }

    private func isRunningInAPNSProductionEnvironment() -> Bool {
        BuildDetails.shared.isTestFlightBuild()
    }
}

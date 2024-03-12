//
//  G7CGMManager+UI.swift
//  CGMBLEKitUI
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import G7SensorKit
import LoopKitUI
import LoopKit

public struct G7DeviceStatusHighlight: DeviceStatusHighlight, Equatable {
    public let localizedMessage: String
    public let imageName: String
    public let state: DeviceStatusHighlightState
    init(localizedMessage: String, imageName: String, state: DeviceStatusHighlightState) {
        self.localizedMessage = localizedMessage
        self.imageName = imageName
        self.state = state
    }
}

extension G7CGMManager: CGMManagerUI {

    public static var onboardingImage: UIImage? {
        return nil
    }

    public static func setupViewController(bluetoothProvider: LoopKit.BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopKitUI.LoopUIColorPalette, allowDebugFeatures: Bool, prefersToSkipUserInteraction: Bool) -> LoopKitUI.SetupUIResult<LoopKitUI.CGMManagerViewController, LoopKitUI.CGMManagerUI>
    {
        let vc = G7UICoordinator(colorPalette: colorPalette, displayGlucosePreference: displayGlucosePreference, allowDebugFeatures: allowDebugFeatures)
        return .userInteractionRequired(vc)
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) ->CGMManagerViewController {

        return G7UICoordinator(cgmManager: self, colorPalette: colorPalette, displayGlucosePreference: displayGlucosePreference, allowDebugFeatures: allowDebugFeatures)
    }

    public var smallImage: UIImage? {
        UIImage(named: "g7", in: Bundle(for: G7SettingsViewModel.self), compatibleWith: nil)!
    }

    // TODO Placeholder.
    public var cgmStatusHighlight: DeviceStatusHighlight? {

        if lifecycleState == .searching {
            return G7DeviceStatusHighlight(
                localizedMessage: LocalizedString("Searching for\nSensor", comment: "G7 Status highlight text for searching for sensor"),
                imageName: "dot.radiowaves.left.and.right",
                state: .normalCGM)
        }

        if lifecycleState == .expired {
            return G7DeviceStatusHighlight(
                localizedMessage: LocalizedString("Sensor\nExpired", comment: "G7 Status highlight text for sensor expired"),
                imageName: "clock",
                state: .normalCGM)
        }

        if lifecycleState == .failed {
            return G7DeviceStatusHighlight(
                localizedMessage: LocalizedString("Sensor\nFailed", comment: "G7 Status highlight text for sensor failed"),
                imageName: "exclamationmark.circle.fill",
                state: .critical)
        }

        if let latestReadingReceivedAt = state.latestReadingTimestamp, latestReadingReceivedAt.timeIntervalSinceNow < -.minutes(15) {
            return G7DeviceStatusHighlight(
                localizedMessage: LocalizedString("Signal\nLoss", comment: "G7 Status highlight text for signal loss"),
                imageName: "exclamationmark.circle.fill",
                state: .warning)
        }

        if let latestReading = latestReading, latestReading.algorithmState.isInSensorError {
            return G7DeviceStatusHighlight(
                localizedMessage: LocalizedString("Sensor\nIssue", comment: "G7 Status highlight text for sensor error"),
                imageName: "exclamationmark.circle.fill",
                state: .warning)
        }

        if lifecycleState == .warmup {
            return G7DeviceStatusHighlight(
                localizedMessage: LocalizedString("Sensor\nWarmup", comment: "G7 Status highlight text for sensor warmup"),
                imageName: "clock",
                state: .normalCGM)
        }
        return nil
    }

    // TODO Placeholder.
    public var cgmStatusBadge: DeviceStatusBadge? {
        if lifecycleState == .gracePeriod {
            return G7DeviceStatusBadge(image: UIImage(systemName: "clock"), state: .critical)
        }
        return nil
    }

    // TODO Placeholder.
    public var cgmLifecycleProgress: DeviceLifecycleProgress? {
        switch lifecycleState {
        case .ok:
            // show remaining lifetime, if < 24 hours
            guard let expiration = sensorExpiresAt else {
                return nil
            }
            let remaining = max(0, expiration.timeIntervalSinceNow)

            if remaining < .hours(24) {
                return G7LifecycleProgress(percentComplete: 1-(remaining/G7Sensor.lifetime), progressState: .warning)
            }
            return nil
        case .gracePeriod:
            guard let endTime = sensorEndsAt else {
                return nil
            }
            let remaining = max(0, endTime.timeIntervalSinceNow)
            return G7LifecycleProgress(percentComplete: 1-(remaining/G7Sensor.gracePeriod), progressState: .critical)
        case .expired:
            return G7LifecycleProgress(percentComplete: 1, progressState: .critical)
        default:
            return nil
        }
    }
}

struct G7DeviceStatusBadge: DeviceStatusBadge {
    var image: UIImage?

    var state: LoopKitUI.DeviceStatusBadgeState
}


struct G7LifecycleProgress: DeviceLifecycleProgress {
    var percentComplete: Double

    var progressState: LoopKit.DeviceLifecycleProgressState
}

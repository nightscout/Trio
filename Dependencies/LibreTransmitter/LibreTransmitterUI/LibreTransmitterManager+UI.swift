//
//  LibreTransmitterManager+UI.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit
import LibreTransmitter
import Combine

struct LibreLifecycleProgress: DeviceLifecycleProgress {
    var percentComplete: Double

    var progressState: LoopKit.DeviceLifecycleProgressState
}

extension LibreTransmitterManagerV3: CGMManagerUI {

    public var cgmStatusBadge: DeviceStatusBadge? {
        nil
    }

    public static func setupViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, prefersToSkipUserInteraction: Bool) -> SetupUIResult<CGMManagerViewController, CGMManagerUI>
    {
        let cgmManager = self.init()
        let vc = LibreTransmitterSetupViewController(displayGlucosePreference: displayGlucosePreference, cgmManager: cgmManager)

        return .userInteractionRequired(vc)
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> CGMManagerViewController {

        let doneNotifier = GenericObservableObject()
        let wantToTerminateNotifier = GenericObservableObject()
        
        let wantToResetCGMManagerNotifier = GenericObservableObject()
        
        let wantToRestablishConnectionNotifier = GenericObservableObject()

        let settingsView = SettingsView(
            transmitterInfo: self.transmitterInfoObservable,
            sensorInfo: self.sensorInfoObservable,
            glucoseMeasurement: self.glucoseInfoObservable,
            notifyComplete: doneNotifier,
            notifyDelete: wantToTerminateNotifier,
            notifyReset: wantToResetCGMManagerNotifier,
            notifyReconnect:wantToRestablishConnectionNotifier,
            alarmStatus: self.alarmStatus,
            pairingService: self.pairingService,
            bluetoothSearcher: self.bluetoothSearcher
        )

        let hostedView = DismissibleHostingController(
            content: settingsView
                .navigationTitle(self.localizedTitle)
                .environmentObject(displayGlucosePreference)
        )

        let nav = CGMManagerSettingsNavigationViewController(rootViewController: hostedView)
        nav.navigationItem.largeTitleDisplayMode = .always
        nav.navigationBar.prefersLargeTitles = true
        
        wantToResetCGMManagerNotifier.listenOnce { [weak self] in
            self?.logger.debug("CGM wants to reset cgmmanager")
            self?.resetManager()

        }
        
        wantToRestablishConnectionNotifier.listenOnce { [weak self, weak nav] in
            self?.logger.debug("CGM wants to RestablishConnection")
            self?.establishProxy()
            nav?.notifyComplete()
        }
        
        doneNotifier.listenOnce { [weak nav] in
            nav?.notifyComplete()

        }

        wantToTerminateNotifier.listenOnce { [weak self, weak nav] in
            self?.logger.debug("CGM wants to terminate")
            self?.disconnect()

            UserDefaults.standard.preSelectedDevice = nil
            self?.notifyDelegateOfDeletion {
                DispatchQueue.main.async {
                    nav?.notifyComplete()

                }
            }

        }

        return nav
    }

    public var cgmStatusHighlight: DeviceStatusHighlight? {
        nil
    }

    public var cgmLifecycleProgress: DeviceLifecycleProgress? {
        if self.sensorInfoObservable.activatedAt == nil {
            // This is the initial state before the plugin
            // has connected to the sensor and retrieved its cgmLifecycleProgress
            // We could show 0 here, but UX-wise it's probably wiser to not do so
            return nil
        }
        
        let minutesLeft = Double(self.sensorInfoObservable.sensorMinutesLeft)
        
        // This matches the manufacturere's app where it displays a notification when sensor has less than 3 days left
        if TimeInterval(minutes: minutesLeft) < TimeInterval(hours: 24*3) {
            let progress = self.sensorInfoObservable.calculateProgress()
            if TimeInterval(minutes: minutesLeft) < TimeInterval(hours: 24) {
                return LibreLifecycleProgress(percentComplete: progress, progressState: .warning)
            }
            return LibreLifecycleProgress(percentComplete: progress, progressState: .normalCGM)
        }
        
        return nil
        
    }
}

extension LibreTransmitterManagerV3: DeviceManagerUI {
    public static var onboardingImage: UIImage? {
        nil
    }

    public var smallImage: UIImage? {
       self.getSmallImage()
    }
}

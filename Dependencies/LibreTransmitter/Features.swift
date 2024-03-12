//
//  Features.swift
//  LibreTransmitter
//
//  Created on 30/08/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

import CoreNFC

public final class Features {

    static public var logSubsystem = "com.loopkit.libre"
    
    static public var glucoseSettingsRequireAuthentication = false
    static public var alarmSettingsViewRequiresAuthentication = false
    
    static public var allowsEditingFactoryCalibrationData = false
    
    // Uses Vibration through apples audio api for glucose alarms. This could be considered an api abuse from apple's standpoint;
    // since apis invoked for this feature are meant for audio streaming apps.
    // However, there are a couple of good reason for keeping this feature, but behind a featureflag rather than a gui toggle:
    // * For heavy sleepers, the combination of an alarm at 100% volume + vibration makes it much more likely to wake up during nighttime.
    // * For this feature to work as intended, Loops info.plist much be amended with "audio" permissions,
    //      see Loop->Signing & Capabilities->Background Modes->"Audio, AirPlay, Picture in picture" in xcode
    static public var glucoseAlarmsAlsoCauseVibration = false
    
    static var phoneNFCAvailable: Bool {
        return NFCNDEFReaderSession.readingAvailable
    }
}

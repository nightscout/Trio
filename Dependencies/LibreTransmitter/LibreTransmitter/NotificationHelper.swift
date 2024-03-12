//
//  NotificationHelper.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 30/05/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import AudioToolbox
import Foundation
import HealthKit
import LoopKit
import UserNotifications
import os.log

private var logger = Logger(forType: "NotificationHelper")
// MARK: - Notification Utilities
public enum NotificationHelper {

    private enum Identifiers: String {
        case glucocoseNotifications = "com.loopkit.libremiaomiao.glucose-notification"
        case noSensorDetected = "com.loopkit.libremiaomiao.nosensordetected-notification"
        case tryAgainLater = "com.loopkit.libremiaomiao.glucoseNotAvailableTryAgainLater-notification"
        case sensorChange = "com.loopkit.libremiaomiao.sensorchange-notification"
        case invalidSensor = "com.loopkit.libremiaomiao.invalidsensor-notification"
        case lowBattery = "com.loopkit.libremiaomiao.lowbattery-notification"
        case sensorExpire = "com.loopkit.libremiaomiao.SensorExpire-notification"
        case noBridgeSelected = "com.loopkit.libremiaomiao.noBridgeSelected-notification"
        case invalidChecksum = "com.loopkit.libremiaomiao.invalidChecksum-notification"
        case calibrationOngoing = "com.loopkit.libremiaomiao.calibration-notification"
        case libre2directFinishedSetup = "com.loopkit.libremiaomiao.libre2direct-notification"
    }
    
    public static var shouldRequestCriticalPermissions = false
    
    // don't touch this please
    public static var criticalAlarmsEnabled = false

    

    private static func vibrate(times: Int=3) {
        guard times >= 0 else {
            return
        }
        

        AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate) {
            vibrate(times: times - 1)
        }
    }

    public static func GlucoseUnitIsSupported(unit: HKUnit) -> Bool {
        [HKUnit.milligramsPerDeciliter, HKUnit.millimolesPerLiter].contains(unit)
    }

    private static func requestCriticalNotificationPermissions() {
        logger.debug("\(#function) called")
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.badge, .sound, .alert, .criticalAlert]) { (granted, error) in
            if granted {
                logger.debug("\(#function) was granted")
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    logPermissions(settings)
                    criticalAlarmsEnabled = settings.criticalAlertSetting == .enabled
                }
            } else {
                logger.debug("\(#function) failed because of error: \(String(describing: error))")
            }

        }

    }
    
    private static func logPermissions(_ settings: UNNotificationSettings, caller: String = #function) {
        
        logger.debug("\(caller): alarms allowed: \(String(describing:settings.authorizationStatus)). Critical alarms allowed? \(String(describing:settings.criticalAlertSetting))")
        
    }

    public static func requestNotificationPermissionsIfNeeded() {
        // We assume loop will request necessary "non-critical" permissions for us
        // So we are only interested in the "critical" permissions here
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            criticalAlarmsEnabled = settings.criticalAlertSetting == .enabled
            logPermissions(settings)
            
            if shouldRequestCriticalPermissions || NotificationHelperOverride.shouldOverrideRequestCriticalPermissions {
                requestCriticalNotificationPermissions()
            }
            
        }
    }

    private static func ensureCanSendNotification(_ completion: @escaping () -> Void ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                logger.debug("\(#function) failed, authorization denied")
                return
            }
            logger.debug("\(#function) sending notification was allowed")

            completion()
        }
    }

    private static func addRequest(identifier: Identifiers, content: UNMutableNotificationContent, deleteOld: Bool = false, isCritical: Bool = false) {
        let center = UNUserNotificationCenter.current()
        
        if isCritical && Self.criticalAlarmsEnabled {
            logger.debug("\(#function) critical alarm created")
            content.interruptionLevel =   .critical
            
            let criticalVolume = UserDefaults.standard.mmCriticalAlarmsVolume < 60 ? 60 : UserDefaults.standard.mmCriticalAlarmsVolume
            logger.debug("\(#function) setting criticalVolume to \(criticalVolume)%")
            content.sound = .defaultCriticalSound(withAudioVolume: Float(criticalVolume / 100))
        } else {
            logger.debug("\(#function) timesensitive alarm created")
            content.interruptionLevel = .timeSensitive
        }
        
        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: nil)

        if deleteOld {
            // Required since ios12+ have started to cache/group notifications
            center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }

        center.add(request) { error in
            if let error {
                logger.debug("\(#function) unable to addNotificationRequest: \(error.localizedDescription)")
                return
            }

            logger.debug("\(#function) sending \(identifier.rawValue) notification")
        }
    }
    
}

// MARK: Sensor related notification sendouts
public extension NotificationHelper {
    static func sendLibre2DirectFinishedSetupNotifcation() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Libre 2 Direct Setup Complete"
            content.body = "Establishing initial connection can take up to 4 minutes. Keep your phone unlocked and Loop in the foreground while connecting"

            addRequest(identifier: .libre2directFinishedSetup, content: content)
        }
    }
    
    static func sendSensorNotDetectedNotificationIfNeeded(noSensor: Bool) {
        guard UserDefaults.standard.mmAlertNoSensorDetected && noSensor else {
            logger.debug("\(#function) Not sending noSensorDetected notification")
            return
        }

        sendSensorNotDetectedNotification()
    }

    private static func sendSensorNotDetectedNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "No Sensor Detected"
            content.body = "This might be an intermittent problem, but please check that your transmitter is tightly secured over your sensor"

            addRequest(identifier: .noSensorDetected, content: content)
        }
    }

    static func sendSensorChangeNotificationIfNeeded() {
        guard UserDefaults.standard.mmAlertNewSensorDetected else {
            logger.debug("\(#function) not sending sendSensorChange notification ")
            return
        }
        sendSensorChangeNotification()
    }

    static func sendSensorChangeNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "New Sensor Detected"
            content.body = "Please wait up to 30 minutes before glucose readings are available!"

            addRequest(identifier: .sensorChange, content: content)
            // content.sound = UNNotificationSound.

        }
    }

    static func sendSensorTryAgainLaterNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Invalid Glucose sample detected, try again later"
            content.body = "Sensor might have temporarily stopped, fallen off or is too cold or too warm"

            addRequest(identifier: .tryAgainLater, content: content)
            // content.sound = UNNotificationSound.

        }
    }

    static func sendInvalidSensorNotificationIfNeeded(sensorData: SensorData) {
        let isValid = sensorData.isLikelyLibre1FRAM && (sensorData.state == .starting || sensorData.state == .ready)

        guard UserDefaults.standard.mmAlertInvalidSensorDetected && !isValid else {
            logger.debug("\(#function) not sending invalidSensorDetected notification")
            return
        }

        sendInvalidSensorNotification(sensorData: sensorData)
    }

    enum CalibrationMessage: String {
        case starting = "Calibrating sensor, please stand by!"
        case noCalibration = "Could not calibrate sensor, check libreoopweb permissions and internet connection"
        case invalidCalibrationData = "Could not calibrate sensor, invalid calibrationdata"
        case success = "Success!"
    }

    static func sendCalibrationNotification(_ calibrationMessage: CalibrationMessage) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.title = "Extracting calibrationdata from sensor"
            content.body = calibrationMessage.rawValue

            addRequest(identifier: .calibrationOngoing,
                       content: content,
                       deleteOld: true)
        }
    }

    static func sendInvalidSensorNotification(sensorData: SensorData) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Invalid Sensor Detected"

            if !sensorData.isLikelyLibre1FRAM {
                content.body = "Detected sensor seems not to be a libre 1 sensor!"
            } else if !(sensorData.state == .starting || sensorData.state == .ready) {
                content.body = "Detected sensor is invalid: \(sensorData.state.description)"
            }

            content.sound = .default

            addRequest(identifier: .invalidSensor, content: content)
        }
    }

    private static var lastSensorExpireAlert: Date?

    static func sendSensorExpireAlertIfNeeded(minutesLeft: Double) {
        guard UserDefaults.standard.mmAlertWillSoonExpire else {
            logger.debug("\(#function) mmAlertWillSoonExpire toggle was not enabled, not sending expiresoon alarm")
            return
        }

        guard TimeInterval(minutes: minutesLeft) < TimeInterval(hours: 24) else {
            logger.debug("\(#function) Sensor time left was more than 24 hours, not sending notification: \(minutesLeft.twoDecimals) minutes")
            return
        }

        let now = Date()
        // only once per 6 hours
        let min45 = 60.0 * 60 * 6

        if let earlier = lastSensorExpireAlert {
            if earlier.addingTimeInterval(min45) < now {
                sendSensorExpireAlert(minutesLeft: minutesLeft)
                lastSensorExpireAlert = now
            } else {
                logger.debug("\(#function) Sensor is soon expiring, but lastSensorExpireAlert was sent less than 6 hours ago, so aborting")
            }
        } else {
            sendSensorExpireAlert(minutesLeft: minutesLeft)
            lastSensorExpireAlert = now
        }
    }

    static func sendSensorExpireAlertIfNeeded(sensorData: SensorData) {
        sendSensorExpireAlertIfNeeded(minutesLeft: Double(sensorData.minutesLeft))
    }

    private static func sendSensorExpireAlert(minutesLeft: Double) {
        ensureCanSendNotification {

            let hours = minutesLeft == 0 ? 0 : round(minutesLeft/60)

            let dynamicText =  hours <= 1 ?  "minutes: \(minutesLeft.twoDecimals)" : "hours: \(hours.twoDecimals)"

            let content = UNMutableNotificationContent()
            content.title = "Sensor Ending Soon"
            content.body = "Current Sensor is Ending soon! Sensor Life left in \(dynamicText)"

            addRequest(identifier: .sensorExpire, content: content, deleteOld: true, isCritical: true)
        }
    }
}

// MARK: - Notification sendout
public extension NotificationHelper {
   

    static func sendNoTransmitterSelectedNotification() {
        ensureCanSendNotification {
            logger.debug("\(#function) sending NoTransmitterSelectedNotification")

            let content = UNMutableNotificationContent()
            content.title = "No Libre Transmitter Selected"
            content.body = "Delete CGMManager and start anew. Your libreoopweb credentials will be preserved"

            addRequest(identifier: .noBridgeSelected, content: content)
        }
    }

    static func sendInvalidChecksumIfDeveloper(_ sensorData: SensorData) {
        guard UserDefaults.standard.dangerModeActivated else {
            return
        }

        if sensorData.hasValidCRCs {
            return
        }

        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Invalid libre checksum"
            content.body = "Libre sensor was incorrectly read, CRCs were not valid"

            addRequest(identifier: .invalidChecksum, content: content)
        }
    }

    private static var glucoseNotifyCalledCount = 0

    static func sendGlucoseNotificationIfNeeded(glucose: LibreGlucose, oldValue: LibreGlucose?, trend: GlucoseTrend?, battery: String?, glucoseFormatter: QuantityFormatter) {
        glucoseNotifyCalledCount &+= 1

        let shouldSendGlucoseAlternatingTimes = glucoseNotifyCalledCount != 0 && UserDefaults.standard.mmNotifyEveryXTimes != 0

        let shouldSend = UserDefaults.standard.mmAlwaysDisplayGlucose || glucoseNotifyCalledCount == 1 ||
            (shouldSendGlucoseAlternatingTimes && glucoseNotifyCalledCount % UserDefaults.standard.mmNotifyEveryXTimes == 0)

        let schedules = UserDefaults.standard.glucoseSchedules

        let alarm = schedules?.getActiveAlarms(glucose.glucoseDouble) ?? .none
        let isSnoozed = GlucoseScheduleList.isSnoozed()

        let shouldShowPhoneBattery = UserDefaults.standard.mmShowPhoneBattery
        let transmitterBattery = UserDefaults.standard.mmShowTransmitterBattery && battery != nil ? battery : nil

        logger.debug("\(#function) glucose alarmtype is \(String(describing: alarm))")
        // We always send glucose notifications when alarm is active,
        // even if glucose notifications are disabled in the UI

        if shouldSend || alarm.isAlarming() {
            sendGlucoseNotification(glucose: glucose, oldValue: oldValue,
                                    glucoseFormatter: glucoseFormatter,
                                    alarm: alarm, isSnoozed: isSnoozed,
                                    trend: trend, showPhoneBattery: shouldShowPhoneBattery,
                                    transmitterBattery: transmitterBattery)
        } else {
            logger.debug("\(#function) not sending glucose, shouldSend and alarmIsActive was false")
            return
        }
    }

    private static func sendGlucoseNotification(glucose: LibreGlucose, oldValue: LibreGlucose?,
                                                glucoseFormatter: QuantityFormatter,
                                                alarm: GlucoseScheduleAlarmResult = .none,
                                                isSnoozed: Bool = false,
                                                trend: GlucoseTrend?,
                                                showPhoneBattery: Bool = false,
                                                transmitterBattery: String?) {
        let content = UNMutableNotificationContent()
        let glucoseDesc = glucoseFormatter.string(from: glucose.quantity)!
        var titles = [String]()
        var body = [String]()
        var body2 = [String]()

        var isCritical = false
        switch alarm {
        case .none:
            titles.append("Glucose")
        case .low:
            titles.append("LOWALERT!")
            isCritical = true
        case .high:
            titles.append("HIGHALERT!")
            isCritical = true
        }

        if isSnoozed {
            titles.append("(Snoozed)")
        } else if alarm.isAlarming() {
            content.sound = .default
            
            if Features.glucoseAlarmsAlsoCauseVibration {
                vibrate()
            }
            
        }
        titles.append(glucoseDesc)

        body.append("Glucose: \(glucoseDesc)")

        if let oldValue {
            let diff = glucose.glucoseDouble - oldValue.glucoseDouble
            if diff >= 0 {
                body.append("+")
            }
            body.append( glucoseFormatter.string(from: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: diff))!)
        }

        if let trend = trend?.localizedDescription {
            body.append("\(trend)")
        }

        if showPhoneBattery {
            if !UIDevice.current.isBatteryMonitoringEnabled {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }

            let battery = Double(UIDevice.current.batteryLevel * 100 ).roundTo(places: 1)
            body2.append("Phone: \(battery)%")
        }

        if let transmitterBattery {
            body2.append("Transmitter: \(transmitterBattery)")
        }

        // these are texts that naturally fit on their own line in the body
        var body2s = ""
        if !body2.isEmpty {
            body2s = "\n" + body2.joined(separator: "\n")
        }

        content.title = titles.joined(separator: " ")
        content.body = body.joined(separator: ", ") + body2s
        addRequest(identifier: .glucocoseNotifications,
                   content: content,
                   deleteOld: true, isCritical: isCritical && !isSnoozed)
    }

    private static var lastBatteryWarning: Date?

    static func sendLowBatteryNotificationIfNeeded(device: LibreTransmitterMetadata) {
        guard UserDefaults.standard.mmAlertLowBatteryWarning else {
            logger.debug("\(#function) mmAlertLowBatteryWarning toggle was not enabled, not sending low notification")
            return
        }

        if let battery = device.battery, battery > 20 {
            logger.debug("\(#function) device battery is \(battery), not sending low notification")
            return

        }

        let now = Date()
        // only once per mins minute
        let mins = 60.0 * 120
        if let earlierplus = lastBatteryWarning?.addingTimeInterval(mins) {
            if earlierplus < now {
                sendLowBatteryNotification(batteryPercentage: device.batteryString,
                                           deviceName: device.name)
                lastBatteryWarning = now
            } else {
                logger.debug("\(#function) Device battery is running low, but lastBatteryWarning Notification was sent less than 45 minutes ago, aborting. earlierplus: \(earlierplus), now: \(now)")
            }
        } else {
            sendLowBatteryNotification(batteryPercentage: device.batteryString,
                                       deviceName: device.name)
            lastBatteryWarning = now
        }
    }

    private static func sendLowBatteryNotification(batteryPercentage: String, deviceName: String) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Low Battery"
            content.body = "Battery is running low (\(batteryPercentage)), consider charging your \(deviceName) device as soon as possible"
            content.sound = .default

            addRequest(identifier: .lowBattery, content: content)
        }
    }

}

//
//  NotificationSettingsView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 27/05/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine
import LibreTransmitter
import HealthKit
import LoopKitUI

struct NotificationSettingsView: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    @State private var presentableStatus: StatusMessage?

    private let glucoseSegments = [HKUnit.millimolesPerLiter, HKUnit.milligramsPerDeciliter]
    private lazy var glucoseSegmentStrings = self.glucoseSegments.map({ $0.localizedShortUnitString })

    private enum Key: String {
        // case glucoseSchedules = "com.loopkit.libreglucoseschedules"

        case mmAlwaysDisplayGlucose = "com.loopkit.libreAlwaysDisplayGlucose"
        case mmNotifyEveryXTimes = "com.loopkit.libreNotifyEveryXTimes"
        case mmAlertLowBatteryWarning = "com.loopkit.libreLowBatteryWarning"
        case mmAlertInvalidSensorDetected = "com.loopkit.libreInvalidSensorDetected"
        // case mmAlertalarmNotifications
        case mmAlertNewSensorDetected = "com.loopkit.libreNewSensorDetected"
        case mmAlertNoSensorDetected = "com.loopkit.libreNoSensorDetected"

        case mmAlertSensorSoonExpire = "com.loopkit.libreAlertSensorSoonExpire"

        case mmShowPhoneBattery = "com.loopkit.libreShowPhoneBattery"
        case mmShowTransmitterBattery = "com.loopkit.libreShowTransmitterBattery"

        // handle specially:
        case mmGlucoseUnit = "com.loopkit.libreGlucoseUnit"
        
    }

    @AppStorage(Key.mmAlwaysDisplayGlucose.rawValue) var mmAlwaysDisplayGlucose: Bool = true
    @AppStorage(Key.mmNotifyEveryXTimes.rawValue) var mmNotifyEveryXTimes: Int = 0
    @AppStorage(Key.mmShowPhoneBattery.rawValue) var mmShowPhoneBattery: Bool = false
    @AppStorage(Key.mmShowTransmitterBattery.rawValue) var mmShowTransmitterBattery: Bool = true

    @AppStorage(Key.mmAlertLowBatteryWarning.rawValue) var mmAlertLowBatteryWarning: Bool = true
    @AppStorage(Key.mmAlertInvalidSensorDetected.rawValue) var mmAlertInvalidSensorDetected: Bool = true
    @AppStorage(Key.mmAlertNewSensorDetected.rawValue) var mmAlertNewSensorDetected: Bool = true
    @AppStorage(Key.mmAlertNoSensorDetected.rawValue) var mmAlertNoSensorDetected: Bool = true
    @AppStorage(Key.mmAlertSensorSoonExpire.rawValue) var mmAlertSensorSoonExpire: Bool = true


    // especially handled mostly for backward compat
    @AppStorage(Key.mmGlucoseUnit.rawValue) var mmGlucoseUnit: String = ""

    @State var notifyErrorState = FormErrorState()

    @State private var favoriteGlucoseUnit = 0

    static let formatter = NumberFormatter()

    var glucoseVisibilitySection : some View {
        Section(header: Text(LocalizedString("Glucose Notification visibility", comment: "Text describing header for notification visibility in notificationsettingsview")) ) {
            Toggle(LocalizedString("Always Notify Glucose", comment: "Text describing always notify glucose option in notificationsettingsview"), isOn: $mmAlwaysDisplayGlucose)

            HStack {
                Text(LocalizedString("Notify per reading", comment: "Text describing option for letting user choose notifying for every reading, every second reading etc"))
                TextField("", value: $mmNotifyEveryXTimes, formatter: Self.formatter)
                    .multilineTextAlignment(.center)
                    .disabled(true)
                    .frame(minWidth: 15, maxWidth: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Stepper("Value", value: $mmNotifyEveryXTimes, in: 0...9)
                    .labelsHidden()

            }.clipped()

            
            Toggle("Adds Transmitter Battery", isOn: $mmShowTransmitterBattery)
            

        }
    }

    var additionalNotificationsSection : some View {
        Section(header: Text(LocalizedString("Additional notification types", comment: "Text describing heading for additional notification types for third party transmitters"))) {
            Toggle("Low battery", isOn: $mmAlertLowBatteryWarning)
            Toggle("Invalid sensor", isOn: $mmAlertInvalidSensorDetected)
            Toggle("Sensor change", isOn: $mmAlertNewSensorDetected)
            Toggle("Sensor not found", isOn: $mmAlertNoSensorDetected)
            Toggle("Sensor expires soon", isOn: $mmAlertSensorSoonExpire)

        }
    }

    /*var miscSection : some View {
        Section(header: Text("Misc")) {
            HStack {
                Text("Unit override")
                Picker(selection: $favoriteGlucoseUnit, label: Text("Unit override")) {
                    Text(HKUnit.millimolesPerLiter.localizedShortUnitString).tag(0)
                    Text(HKUnit.milligramsPerDeciliter.localizedShortUnitString).tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .clipped()
            }
        }
    }*/

    var body: some View {
        List {

            glucoseVisibilitySection
            additionalNotificationsSection

        }
        .listStyle(InsetGroupedListStyle())
        .alert(item: $presentableStatus) { status in
            Alert(title: Text(status.title), message: Text(status.message), dismissButton: .default(Text("Got it!")))
        }

        .navigationBarTitle("Notification")

    }

}

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView()
    }
}

//
//  TestView.swift
//  MiaomiaoClientUI
//
//  Created by LoopKit Authors on 15/10/2020.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LibreTransmitter
import SwiftUI

struct SnoozeView: View {

    var pickerTimes: [TimeInterval] = ({
        pickerTimesArray()

    })()

    var formatter: DateComponentsFormatter = ({
        var f = DateComponentsFormatter()
        f.allowsFractionalUnits = false
        f.unitsStyle = .full
        return f

    })()

    func formatInterval(_ interval: TimeInterval) -> String {
        formatter.string(from: interval)!
    }

    @Binding var isAlarming: Bool
    @Binding var activeAlarms: LibreTransmitter.GlucoseScheduleAlarmResult

    static func pickerTimesArray() -> [TimeInterval] {
        var arr  = [TimeInterval]()

        let mins10 = 0.166_67
        let mins20 = mins10 * 2
        let mins30 = mins10 * 3
        // let mins40 = mins10 * 4

        for hr in 0..<2 {
            for min in [0.0, mins20, mins20 * 2] {
                arr.append(TimeInterval(hours: Double(hr) + min))
            }
        }
        for hr in 2..<4 {
            for min in [0.0, mins30] {
                arr.append(TimeInterval(hours: Double(hr) + min))
            }
        }

        for hr in 4...8 {
            arr.append(TimeInterval(hours: Double(hr)))
        }

        return arr
    }

    func getSnoozeDescription() -> String {
        var snoozeDescription  = ""
        var celltext = ""

        switch activeAlarms {
        case .high:
            celltext = "High Glucose Alarm active"
        case .low:
            celltext = "Low Glucose Alarm active"
        case .none:
            celltext = "No Glucose Alarm active"
        }

        if let until = GlucoseScheduleList.snoozedUntil {
            snoozeDescription = "snoozing until \(until.description(with: .current))"
        } else {
            snoozeDescription = "not snoozing"
        }

        return [celltext, snoozeDescription].joined(separator: ", ")
    }

    @State private var selectedInterval = 0
    @State private var snoozeDescription = "nothing to see here"

    var snoozeButton: some View {
        VStack(alignment: .leading) {
            Button(action: {
                print("snooze from testview clicked")
                let interval = pickerTimes[selectedInterval]
                let snoozeFor = formatter.string(from: interval)!
                let untilDate = Date() + interval
                UserDefaults.standard.snoozedUntil = untilDate < Date() ? nil : untilDate
                print("will snooze for \(snoozeFor) until \(untilDate.description(with: .current))")
                snoozeDescription = getSnoozeDescription()
            }, label: {
                Text(LocalizedString("Click to Snooze Alerts", comment: "Text describing click to snooze label in snoozeview"))
                    .padding()
            })
        }

    }

    var snoozePicker: some View {
        VStack {
            Picker(selection: $selectedInterval, label: Text("Strength")) {
                ForEach(0 ..< pickerTimes.count, id: \.self) {
                    Text(formatInterval(self.pickerTimes[$0]))
                }
            }

            .scaledToFill()
            .pickerStyle(.wheel)
        }

    }

    var snoozeDesc : some View {
        VStack(alignment: .leading) {
            Text(snoozeDescription)
        }
    }

    var body: some View {
        Form {
            Section {
                Text(snoozeDescription).lineLimit(nil)
                snoozePicker
                snoozeButton
            }
        }
        .onAppear {
            snoozeDescription = getSnoozeDescription()
        }
    }
}

struct TestView_Previews: PreviewProvider {
    static var previews: some View {
        SnoozeView(isAlarming: .constant(true), activeAlarms: .constant(.none))
    }
}

import AudioToolbox
import SwiftUI
import Swinject

extension Snooze {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State private var selectedInterval = 0
        @State private var snoozeDescription = "nothing to see here"

        private var pickerTimes: [TimeInterval] {
            var arr: [TimeInterval] = []

            let mins10 = 0.166_67
            let mins20 = mins10 * 2
            let mins30 = mins10 * 3
            // let mins40 = mins10 * 4

            for hr in 0 ..< 2 {
                for min in [0.0, mins20, mins20 * 2] {
                    arr.append(TimeInterval(hours: Double(hr) + min))
                }
            }
            for hr in 2 ..< 4 {
                for min in [0.0, mins30] {
                    arr.append(TimeInterval(hours: Double(hr) + min))
                }
            }

            for hr in 4 ... 8 {
                arr.append(TimeInterval(hours: Double(hr)))
            }

            return arr
        }

        private var formatter: DateComponentsFormatter {
            let formatter = DateComponentsFormatter()
            formatter.allowsFractionalUnits = false
            formatter.unitsStyle = .full
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }

        private func formatInterval(_ interval: TimeInterval) -> String {
            formatter.string(from: interval)!
        }

        func getSnoozeDescription() -> String {
            var snoozeDescription = ""
            var celltext = ""

            switch state.alarm {
            case .high:
                celltext = String(localized: "High Glucose Alarm active", comment: "High Glucose Alarm active")
            case .low:
                celltext = String(localized: "Low Glucose Alarm active", comment: "Low Glucose Alarm active")
            case .none:
                celltext = String(localized: "No Glucose Alarm active", comment: "No Glucose Alarm active")
            }

            if state.snoozeUntilDate > Date() {
                snoozeDescription = String(
                    format: String(localized: "snoozing until %@", comment: "snoozing until %@"),
                    dateFormatter.string(from: state.snoozeUntilDate)
                )
            } else {
                snoozeDescription = String(localized: "not snoozing", comment: "not snoozing")
            }

            return [celltext, snoozeDescription].joined(separator: ", ")
        }

        private var snoozeButton: some View {
            VStack(alignment: .leading) {
                Button {
                    let interval = pickerTimes[selectedInterval]
                    let snoozeFor = formatter.string(from: interval)!
                    let untilDate = Date() + interval
                    state.snoozeUntilDate = untilDate < Date() ? .distantPast : untilDate
                    debug(.default, "will snooze for \(snoozeFor) until \(dateFormatter.string(from: untilDate))")
                    snoozeDescription = getSnoozeDescription()
                    state.hideModal()
                } label: {
                    Text("Click to Snooze Alerts")
                        .padding()
                }
            }
        }

        private var snoozePicker: some View {
            VStack {
                Picker(selection: $selectedInterval, label: Text("Strength")) {
                    ForEach(0 ..< pickerTimes.count) {
                        Text(formatInterval(self.pickerTimes[$0]))
                    }
                }
                .pickerStyle(.wheel)
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
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationBarTitle("Snooze Alerts")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
            .onAppear {
                configureView()
                snoozeDescription = getSnoozeDescription()
            }
        }
    }
}

extension TimeInterval {
    static func seconds(_ seconds: Double) -> TimeInterval {
        seconds
    }

    static func minutes(_ minutes: Double) -> TimeInterval {
        TimeInterval(minutes: minutes)
    }

    static func hours(_ hours: Double) -> TimeInterval {
        TimeInterval(hours: hours)
    }

    init(minutes: Double) {
        // self.init(minutes * 60)
        let m = minutes * 60
        self.init(m)
    }

    init(hours: Double) {
        self.init(minutes: hours * 60)
    }

    var minutes: Double {
        self / 60.0
    }

    var hours: Double {
        minutes / 60.0
    }
}

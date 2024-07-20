import SwiftUI
import Swinject

extension StatConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var carbsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    Toggle("Display Chart X - Grid lines", isOn: $state.xGridLines)
                    Toggle("Display Chart Y - Grid lines", isOn: $state.yGridLines)
                    Toggle("Display Chart Threshold lines for Low and High", isOn: $state.rulerMarks)
                    Toggle("Standing / Laying TIR Chart", isOn: $state.oneDimensionalGraph)
                    Toggle("Enable total insulin in scope", isOn: $state.tins)
                } header: { Text("Home Chart settings ") }

<<<<<<< HEAD
                Section {
=======
                    HStack {
                        Text("Hours X-Axis (6 default)")
                        Spacer()
                        TextFieldWithToolBar(text: $state.hours, placeholder: "6", numberFormatter: carbsFormatter)
                        Text("hours").foregroundColor(.secondary)
                    }

>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                    HStack {
                        Text("Low")
                        Spacer()
                        TextFieldWithToolBar(text: $state.low, placeholder: "0", numberFormatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("High")
                        Spacer()
                        TextFieldWithToolBar(text: $state.high, placeholder: "0", numberFormatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    Toggle("Override HbA1c Unit", isOn: $state.overrideHbA1cUnit)

                } header: { Text("Statistics settings ") }

                Section {
                    Toggle("Skip Bolus screen after carbs", isOn: $state.skipBolusScreenAfterCarbs)
                    Toggle("Display and allow Fat and Protein entries", isOn: $state.useFPUconversion)
                } header: { Text("Add Meal View settings ") }

                Section {
                    Picker(
                        selection: $state.historyLayout,
                        label: Text("History Layout")
                    ) {
                        ForEach(HistoryLayout.allCases) { selection in
                            Text(selection.displayName).tag(selection)
                        }
                    }
                } header: { Text("History Settings") }

                Section {
                    Picker(
                        selection: $state.lockScreenView,
                        label: Text("Lock screen widget")
                    ) {
                        ForEach(LockScreenView.allCases) { selection in
                            Text(selection.displayName).tag(selection)
                        }
                    }
                } header: { Text("Lock screen widget") }
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationBarTitle("UI/UX")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

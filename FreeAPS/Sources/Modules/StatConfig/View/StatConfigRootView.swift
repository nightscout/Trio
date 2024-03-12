import SwiftUI
import Swinject

extension StatConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

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
                    Toggle("Change HbA1c Unit", isOn: $state.overrideHbA1cUnit)
                    Toggle("Display Chart X - Grid lines", isOn: $state.xGridLines)
                    Toggle("Display Chart Y - Grid lines", isOn: $state.yGridLines)
                    Toggle("Display Chart Threshold lines for Low and High", isOn: $state.rulerMarks)

                    HStack {
                        Text("Hours X-Axis (6 default)")
                        Spacer()
                        DecimalTextField("6", value: $state.hours, formatter: carbsFormatter)
                        Text("hours").foregroundColor(.secondary)
                    }
                } header: { Text("Home Chart Settings") }

                Section {
                    Toggle("Standing / Laying TIR Chart", isOn: $state.oneDimensionalGraph)
                    HStack {
                        Text("Low")
                        Spacer()
                        DecimalTextField("0", value: $state.low, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }

                    HStack {
                        Text("High")
                        Spacer()
                        DecimalTextField("0", value: $state.high, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                } header: { Text("Statistics") }

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
            .onAppear(perform: configureView)
            .navigationBarTitle("UI/UX")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

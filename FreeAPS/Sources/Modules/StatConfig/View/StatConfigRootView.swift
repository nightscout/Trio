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
                Section(header: Text("Settings")) {
                    Toggle("Change HbA1c Unit", isOn: $state.overrideHbA1cUnit)
                    Toggle("Display Chart X - Grid lines", isOn: $state.xGridLines)
                    Toggle("Display Chart Y - Grid lines", isOn: $state.yGridLines)
                    Toggle("Display Chart Threshold lines for Low and High", isOn: $state.rulerMarks)
                    Toggle("Standing / Laying TIR Chart", isOn: $state.oneDimensionalGraph)

                    HStack {
                        Text("Hours X-Axis (6 default)")
                        Spacer()
                        TextFieldWithToolBar(text: $state.hours, placeholder: "6", numberFormatter: carbsFormatter)
                        Text("hours").foregroundColor(.secondary)
                    }

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
                }
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Statistics")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

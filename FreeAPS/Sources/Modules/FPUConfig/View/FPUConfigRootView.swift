import SwiftUI
import Swinject

extension FPUConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var intFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            return formatter
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Limit Per Entry")) {
                    HStack {
                        Text("Max Carbs")
                        TextFieldWithToolBar(text: $state.maxCarbs, placeholder: "g", numberFormatter: formatter)
                    }
                    HStack {
                        Text("Max Fat")
                        TextFieldWithToolBar(text: $state.maxFat, placeholder: "g", numberFormatter: formatter)
                    }
                    HStack {
                        Text("Max Protein")
                        TextFieldWithToolBar(text: $state.maxProtein, placeholder: "g", numberFormatter: formatter)
                    }
                }

                Section(header: Text("Fat and Protein Conversion Settings")) {
                    HStack {
                        Text("Delay In Minutes")
                        Spacer()
                        TextFieldWithToolBar(text: $state.delay, placeholder: "60", numberFormatter: intFormater)
                    }
                    HStack {
                        Text("Maximum Duration In Hours")
                        Spacer()
                        TextFieldWithToolBar(text: $state.timeCap, placeholder: "8", numberFormatter: intFormater)
                    }
                    HStack {
                        Text("Interval In Minutes")
                        Spacer()
                        TextFieldWithToolBar(text: $state.minuteInterval, placeholder: "30", numberFormatter: intFormater)
                    }
                    HStack {
                        Text("Override With A Factor Of ")
                        Spacer()
                        TextFieldWithToolBar(text: $state.individualAdjustmentFactor, placeholder: "0.5", numberFormatter: conversionFormatter)
                    }
                }

                Section(
                    footer: Text(
                        "Allows fat and protein to be converted into future carb equivalents using the Warsaw formula of kilocalories divided by 10.\n\nThis spreads the carb equivilants over a maximum duration setting that can be configured from 5-12 hours.\n\nDelay is time from now until the first future carb entry.\n\nInterval in minutes is how many minutes are between entries. The shorter the interval, the smoother the result. 10, 15, 20, 30, or 60 are reasonable choices.\n\nAdjustment factor is how much effect the fat and protein has on the entries. 1.0 is full effect (original Warsaw Method) and 0.5 is half effect. Note that you may find that your normal carb ratio needs to increase to a larger number if you begin adding fat and protein entries. For this reason, it is best to start with a factor of about 0.5 to ease into it.\n\nDefault settings: Time Cap: 8 h, Interval: 30 min, Factor: 0.5, Delay 60 min"
                    )
                )
                    {}
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Meal Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

import SwiftUI
import Swinject

extension PumpSettingsEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Delivery limits")) {
                    HStack {
                        Text("Max Basal")
                        TextFieldWithToolBar(text: $state.maxBasal, placeholder: "U/hr", numberFormatter: formatter)
                    }
                    HStack {
                        Text("Max Bolus")
                        TextFieldWithToolBar(text: $state.maxBolus, placeholder: "U", numberFormatter: formatter)
                    }
                }

                Section(header: Text("Duration of Insulin Action")) {
                    HStack {
                        Text("DIA")
                        TextFieldWithToolBar(text: $state.dia, placeholder: "hours", numberFormatter: formatter)
                    }
                }

                Section {
                    HStack {
                        if state.syncInProgress {
                            ProgressView().padding(.trailing, 10)
                        }
                        Button { state.save() }
                        label: {
                            Text(state.syncInProgress ? "Saving..." : "Save on Pump")
                        }
                        .disabled(state.syncInProgress)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Pump Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

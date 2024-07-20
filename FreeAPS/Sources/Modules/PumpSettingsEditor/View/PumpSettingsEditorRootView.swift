import SwiftUI
import Swinject

extension PumpSettingsEditor {
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
                    // TODO: is max carbs now somewhere else?
//                    HStack {
//                        Text("Max Carbs")
//                        TextFieldWithToolBar(text: $state.maxCarbs, placeholder: "g", numberFormatter: formatter)
//                    }
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
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Pump Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

import SwiftUI
import Swinject

extension ManualTempBasal {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumIntegerDigits = 2
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextFieldWithToolBar(
                            text: $state.rate,
                            placeholder: "0",
                            numberFormatter: formatter,
                            initialFocus: true
                        )
                        Text("U/hr").foregroundColor(.secondary)
                    }
                    Picker(selection: $state.durationIndex, label: Text("Duration")) {
                        ForEach(0 ..< state.durationValues.count) { index in
                            Text(
                                String(
                                    format: "%.0f h %02.0f min",
                                    state.durationValues[index] / 60 - 0.1,
                                    state.durationValues[index].truncatingRemainder(dividingBy: 60)
                                )
                            ).tag(index)
                        }
                    }
                }

                Section {
                    Button { state.enact() }
                    label: { Text("Enact") }
                    Button { state.cancel() }
                    label: { Text("Cancel Temp Basal") }
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Manual Temp Basal")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
        }
    }
}

import SwiftUI
import Swinject

extension PumpSettingsEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

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
                Section(
                    header: Text("Insulin Pump Configuration"),
                    content: {
                        VStack {
                            HStack {
                                Text("Max Basal")
                                Spacer()
                                TextFieldWithToolBar(text: $state.maxBasal, placeholder: "0", numberFormatter: formatter)
                            }.padding(.top)
                            HStack {
                                Text("Max Bolus")
                                Spacer()
                                TextFieldWithToolBar(text: $state.maxBolus, placeholder: "0", numberFormatter: formatter)
                            }

                            HStack(alignment: .top) {
                                Text(
                                    "Sets delivery limits for basal and bolus insulin on pump."
                                )
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Insulin Delivery limits"
                                        selectedVerboseHint = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                                        shouldDisplayHint.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                ).buttonStyle(BorderlessButtonStyle())
                            }
                        }.padding(.bottom)
                    }
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $state.dia,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Duration of Insulin Action"
                        }
                    ),
                    type: .decimal("dia"),
                    label: "Duration of Insulin Action",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Duration of Insulin Action… bla bla bla"
                )

                Section {
                    HStack {
                        if state.syncInProgress {
                            ProgressView().padding(.trailing, 10)
                        }
                        Button {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()
                        } label: {
                            Text(state.syncInProgress ? "Saving..." : "Save")
                        }
                        .disabled(state.syncInProgress || !state.hasChanged)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                    }
                }.listRowBackground(state.syncInProgress || !state.hasChanged ? Color(.systemGray4) : Color(.systemBlue))
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Delivery Limits")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

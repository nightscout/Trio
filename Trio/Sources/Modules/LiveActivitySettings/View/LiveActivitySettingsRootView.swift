import ActivityKit
import SwiftUI
import Swinject

extension LiveActivitySettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @State private var systemLiveActivitySetting: Bool = {
            if #available(iOS 16.2, *) {
                ActivityAuthorizationInfo().areActivitiesEnabled
            } else {
                false
            }
        }()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                if !systemLiveActivitySetting {
                    Section(
                        header: Text("Display Live Data From Trio"),
                        content: {
                            Text("Live Activities must be enabled under iOS Settings to allow Trio to display live data.")
                        }
                    ).listRowBackground(Color.chart)

                    Section {
                        Button {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        }
                        label: { Label("Open iOS Settings", systemImage: "gear.circle").font(.title3).padding() }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.useLiveActivity,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Enable Live Activity")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Enable Live Activity"),
                        miniHint: String(localized: "Display customizable data on Lock Screen and Dynamic Island."),
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "With Live Activities enabled, Trio displays your choice of the following current data on your iPhone's Lock Screen and in the Dynamic Island:"
                                )
                                VStack(alignment: .leading) {
                                    Text("• Current Glucose Reading")
                                    Text("• IOB: Insulin On Board")
                                    Text("• COB: Carbohydrates On Board")
                                    Text("• Last Updated: Time of Last Loop Cycle")
                                    Text("• Glucose Trend Chart")
                                }.font(.footnote)
                                Text(
                                    "It allows you to refer to live information at a glance and perform quick actions in your diabetes management."
                                )
                            }
                        },
                        headerText: String(localized: "Display Live Data From Trio")
                    )

                    if state.useLiveActivity {
                        Section {
                            VStack {
                                Picker(
                                    selection: $state.lockScreenView,
                                    label: Text("Lock Screen Widget Style")
                                ) {
                                    ForEach(LockScreenView.allCases) { selection in
                                        Text(selection.displayName).tag(selection)
                                    }
                                }.padding(.top)

                                HStack(alignment: .center) {
                                    Text(
                                        "Select simple or detailed style. See hint for more details."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = String(localized: "Lock Screen Widget Style")
                                            selectedVerboseHint =
                                                AnyView(
                                                    VStack(alignment: .leading, spacing: 10) {
                                                        Text("Default: Simple").bold()
                                                        VStack(alignment: .leading, spacing: 10) {
                                                            Text("Simple:").bold()
                                                            Text(
                                                                "Trio's Simple Lock Screen Widget displays current glucose reading, trend arrow, delta and the timestamp of the current reading."
                                                            )
                                                        }
                                                        VStack(alignment: .leading, spacing: 10) {
                                                            Text("Detailed:").bold()
                                                            Text(
                                                                "The Detailed Lock Screen Widget offers users a glucose chart as well as the ability to customize the information provided in the Detailed Widget using the following options:"
                                                            )
                                                        }
                                                        VStack(alignment: .leading) {
                                                            Text("• Current Glucose Reading")
                                                            Text("• IOB: Insulin On Board")
                                                            Text("• COB: Carbohydrates On Board")
                                                            Text("• Last Updated: Time of Last Loop Cycle")
                                                        }.font(.footnote)
                                                    }
                                                )
                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.top)
                            }.padding(.bottom)

                            if state.lockScreenView == .detailed {
                                HStack {
                                    NavigationLink(
                                        "Widget Configuration",
                                        destination: LiveActivityWidgetConfiguration(
                                            resolver: resolver,
                                            state: state
                                        )
                                    ).foregroundStyle(Color.accentColor)
                                }
                            }
                        }.listRowBackground(Color.chart)
                    }
                }
            }
            .listSectionSpacing(sectionSpacing)
            .onReceive(resolver.resolve(LiveActivityManager.self)!.$systemEnabled, perform: {
                self.systemLiveActivitySetting = $0
            })
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Live Activity")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

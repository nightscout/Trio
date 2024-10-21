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

        private var color: LinearGradient {
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
                                hintLabel = "Enable Live Activity"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Enable Live Activity",
                        miniHint: "Live Activities display Trio's glucose readings, and other current data on the iPhone Lock Screen and in the Dynamic Island",
                        verboseHint: Text(
                            "With Live Activities, you can let Trio display most current data, e.g. glucose reading from CGM, insulin on board, carbohydrates on board, or even a glucose trend chart, on the iPhone Lock Screen and in the Dynamic Island. It allows you to refer to live information at a glance and perform quick actions in your diabetes management."
                        ),
                        headerText: "Display Live Data From Trio"
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

                                HStack(alignment: .top) {
                                    Text(
                                        "Trio Live Activities can be simplistic or detailed in their information display. See hint for more details."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = "Lock Screen Widget Style"
                                            selectedVerboseHint =
                                                AnyView(
                                                    Text(
                                                        "Trio's simple lock screen widget only display current glucose reading, trend arrow, delta and the timestamp of the current reading.\n\nThe detailed Lock Screen widget offers users a glucose chart, glucose trend arrow, glucose delta, current insulin and carbohydrates on board, and an icon as an indicator for running overrides."
                                                    )
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
            .onReceive(resolver.resolve(LiveActivityBridge.self)!.$systemEnabled, perform: {
                self.systemLiveActivitySetting = $0
            })
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Live Activity")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

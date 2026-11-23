import SwiftUI
import Swinject

struct WatchConfigAppleWatchView: BaseView {
    static let cornerLabelHint = String(
        localized: "Corner Label is the curved text on Trio Glucose corner slots."
    )
    static let smallLineHint = String(
        localized: "Small Line is the text under the glucose on Trio Glucose circular slots, beside the ring on Trio Gauge rectangular slots, and the second line of Trio Chart. Trio IOB has a fixed layout."
    )
    static let markStaleAfterHint = String(
        localized: "Mark Stale After applies to every complication: once the reading is older than this, the glucose shows -- with the reading's age, and IOB and COB show -- when the loop has not run within that time.\n\nComplications can fall behind the phone, sometimes by a lot: with the watch app closed, watchOS limits how often they refresh. The Contact Image updates with every reading, so use it if you want every reading on your watch face."
    )
    static let colorModeHint = String(
        localized: "Color shows the glucose and trend arrow in the colors the phone uses for them. Monochrome shows them in white, which is easier to read in the dark. The gauge ring and the chart line keep their colors either way."
    )

    let resolver: Resolver
    @ObservedObject var state: WatchConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    private func onDelete(offsets: IndexSet) {
        state.devices.remove(atOffsets: offsets)
        state.deleteGarminDevice()
    }

    private var previewState: ComplicationState {
        ComplicationState.sample(
            units: state.units.rawValue,
            settings: ComplicationSlotSettings(
                cornerValue: state.complicationCornerValue,
                secondaryValue: state.complicationSecondaryValue,
                staleMinutes: state.complicationStaleMinutes,
                colorMode: state.complicationColorMode
            ),
            ringStops: state.complicationRingStops
        )
    }

    private func hintRow(miniHint: String, label: String, hint: String) -> some View {
        HStack(alignment: .center) {
            Text(miniHint)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(
                action: {
                    hintLabel = label
                    selectedVerboseHint = AnyView(Text(hint))
                    shouldDisplayHint.toggle()
                },
                label: {
                    Image(systemName: "questionmark.circle").accessibilityLabel(Text("More information"))
                }
            ).buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        List {
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.confirmBolusFaster,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Confirm Bolus Faster")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Confirm Bolus Faster"),
                miniHint: String(localized: "Reduce the number of crown rotations required for bolus confirmation."),
                verboseHint: Text(
                    "Enabling this feature lowers the number of turns on the crown dial required when confirming a bolus."
                ),
                headerText: String(localized: "Apple Watch Configuration")
            )

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.showForecastWatch,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Show forecast on Watch")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Show Forecast on Watch"),
                miniHint: String(localized: "Shows forecast on the Apple Watch"),
                verboseHint: Text(
                    "Enable this feature to show the forecast on the Apple Watch"
                )
            )

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.useCriticalAlertsWatch,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Critical Alerts on Watch")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Critical Alerts on Watch"),
                miniHint: String(localized: "The watch’s urgent low alarm sounds through Silent Mode"),
                verboseHint: Text(
                    "When this is on, the urgent low alarm the watch raises for its own readings sounds even in Silent Mode. The watch asks for permission the first time."
                )
            )

            if state.cgmSharesWithWatch {
                Section(
                    header: Text("Glucose on the Watch"),
                    footer: Text(
                        String(
                            localized: "The watch reads the \(state.cgmName) itself while “Read on Apple Watch” is on in its settings. It shows the iPhone’s readings while they come, and its own, with a watch symbol in the glucose bubble, once they stop."
                        )
                    ),
                    content: {
                        HStack {
                            Text("Read on Apple Watch")
                            Spacer()
                            Text(state.watchReadsSensor ? "On" : "Off").foregroundStyle(.secondary)
                        }
                        NavigationLink(String(localized: "Change in the \(state.cgmName) Settings")) {
                            CGMSettings.RootView(
                                resolver: resolver,
                                displayClose: false,
                                bluetoothManager: resolver.resolve(BluetoothStateManager.self)!
                            )
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                ).listRowBackground(Color.chart)
            }

            Section(
                header: Text("Complication Settings"),
                content: {
                    VStack {
                        Picker("Corner Label", selection: $state.complicationCornerValue) {
                            ForEach(WatchComplicationValue.allCases) { value in
                                Text(value.displayName).tag(value)
                            }
                        }.padding(.top)
                        hintRow(
                            miniHint: String(localized: "Curved text on Trio Glucose corner slots."),
                            label: String(localized: "Corner Label"),
                            hint: Self.cornerLabelHint
                        )
                    }
                }
            ).listRowBackground(Color.chart)

            Section {
                VStack {
                    Picker("Small Line", selection: $state.complicationSecondaryValue) {
                        ForEach(WatchComplicationValue.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }.padding(.top)
                    hintRow(
                        miniHint: String(localized: "Second line on Trio Glucose, Trio Gauge and Trio Chart."),
                        label: String(localized: "Small Line"),
                        hint: Self.smallLineHint
                    )
                }
            }.listRowBackground(Color.chart)

            Section {
                VStack {
                    Stepper(
                        value: $state.complicationStaleMinutes,
                        in: WatchComplicationDefaults.staleMinutesRange,
                        step: WatchComplicationDefaults.staleMinutesStep
                    ) {
                        HStack {
                            Text("Mark Stale After")
                            Spacer()
                            Text("\(state.complicationStaleMinutes) min").foregroundStyle(.secondary)
                        }
                    }.padding(.top)
                    hintRow(
                        miniHint: String(localized: "Show -- once data is older than this. Complications can lag."),
                        label: String(localized: "Mark Stale After"),
                        hint: Self.markStaleAfterHint
                    )
                }
            }.listRowBackground(Color.chart)

            Section {
                VStack {
                    Picker("Color Mode", selection: $state.complicationColorMode) {
                        ForEach(WatchComplicationColorMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }.padding(.top)
                    hintRow(
                        miniHint: String(localized: "Glucose text in color or in white."),
                        label: String(localized: "Color Mode"),
                        hint: Self.colorModeHint
                    )
                }
            }.listRowBackground(Color.chart)

            Section {
                NavigationLink("Complication Previews") {
                    WatchComplicationPreviewsView(preview: previewState)
                }.foregroundStyle(Color.accentColor)
            }.listRowBackground(Color.chart)

            Section(
                header: Text("Contact Image"),
                footer: Text(
                    "Trio draws your glucose into the photo of a contact on your iPhone. Put that contact on a watch face with the Contacts complication: it updates with every reading, also when the Trio complications lag."
                ),
                content: {
                    VStack {
                        HStack {
                            NavigationLink("Contacts Configuration") {
                                ContactImage.RootView(resolver: resolver)
                            }.foregroundStyle(Color.accentColor)
                        }
                    }
                }
            ).listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        // back from the CGM's settings
        .onAppear { state.refreshWatchSensor() }
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.automatic)
        .settingsHighlightScroll()
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}

private struct WatchComplicationPreviewsView: View {
    let preview: ComplicationState

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            Section(
                footer: Text(
                    "Previews use sample data in your units and follow your complication settings. Add them from the watch face editor under Trio. Corner slots curve the label round the face."
                ),
                content: {
                    ForEach(ComplicationKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kind.displayName).font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(kind.slots.filter { $0 != .inline }, id: \.self) { slot in
                                        ComplicationPreview(kind: kind, slot: slot, state: preview)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            Text(kind.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            ).listRowBackground(Color.chart)
        }
        .navigationTitle("Complication Previews")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}

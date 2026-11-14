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
                staleMinutes: state.complicationStaleMinutes
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
                ),
                headerText: String(localized: "Apple Watch Configuration")
            )

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
                }
            ).listRowBackground(Color.chart)

            Section(
                header: Text("Available Complications"),
                content: {
                    NavigationLink("Complication Previews") {
                        WatchComplicationPreviewsView(preview: previewState)
                    }.foregroundStyle(Color.accentColor)
                }
            ).listRowBackground(Color.chart)

            Section(
                header: Text("Contact Image"),
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

import SwiftUI
import Swinject

struct WatchConfigAppleWatchView: BaseView {
    static let complicationSettingsFooter = String(
        localized: "Grey Out After applies to every complication: once the reading is older than this, the glucose shows -- with the reading's age, and IOB and COB show -- when the loop has not run within that time. With the watch app closed, Apple limits how often complications refresh, so expect them to lag the phone by up to about 15 minutes; the Contact Image updates with every reading. Corner Label is the curved text on Trio Glucose corner slots. Small Line is the text under the glucose on Trio Glucose circular slots, beside the ring on Trio Gauge rectangular slots, and the second line of Trio Chart. Trio IOB has a fixed layout."
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
            )
        )
    }

    private func previewSlots(for kind: ComplicationKind) -> [ComplicationSlot] {
        kind.slots.filter { $0 != .inline }
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
                footer: Text(Self.complicationSettingsFooter),
                content: {
                    Picker("Corner Label", selection: $state.complicationCornerValue) {
                        ForEach(WatchComplicationValue.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    Picker("Small Line", selection: $state.complicationSecondaryValue) {
                        ForEach(WatchComplicationValue.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    Stepper(
                        value: $state.complicationStaleMinutes,
                        in: WatchComplicationDefaults.staleMinutesRange,
                        step: WatchComplicationDefaults.staleMinutesStep
                    ) {
                        HStack {
                            Text("Grey Out After")
                            Spacer()
                            Text("\(state.complicationStaleMinutes) min").foregroundStyle(.secondary)
                        }
                    }
                }
            ).listRowBackground(Color.chart)

            Section(
                header: Text("Available Complications"),
                footer: Text(
                    "Previews use sample data in your units and follow the settings above. Add them from the watch face editor under Trio. Corner slots curve the label round the face."
                ),
                content: {
                    let preview = previewState
                    ForEach(ComplicationKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kind.displayName).font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(previewSlots(for: kind), id: \.self) { slot in
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

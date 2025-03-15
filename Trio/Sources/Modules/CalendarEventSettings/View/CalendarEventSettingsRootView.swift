import SwiftUI
import Swinject

extension CalendarEventSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useCalendar,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Create Events in Calendar")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Create Events in Calendar"),
                    miniHint: String(localized: "Use calendar events to display current data."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When enabled, Trio will create a customizable calendar event to keep you notified of your current glucose reading with every successful loop cycle."
                        )
                        Text(
                            "This is useful if you use CarPlay or a variety of other external services that limit the view of most apps, but allow the calendar app."
                        )
                        Text(
                            "Once enabled, the available customizations will appear. You can customize with the calendar of your choosing, use of emoji labels, and the inclusion of IOB & COB data."
                        )
                        Text("Note: Once a new calendar event is created, the previous event will be deleted.")
                    },
                    headerText: String(localized: "Diabetes Data as Calendar Event")
                )

                if state.calendarIDs.isNotEmpty, state.useCalendar {
                    Section {
                        VStack {
                            Picker("Choose Calendar", selection: $state.currentCalendarID) {
                                ForEach(state.calendarIDs, id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                        }
                    }.listRowBackground(Color.chart)

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.displayCalendarEmojis,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Display Emojis as Labels")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Display Emojis as Labels"),
                        miniHint: String(localized: "Use emojis for calendar events. See hint for more details."),
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            VStack(alignment: .leading, spacing: 5) {
                                Text(
                                    "When enabled, the calendar event created will indicate whether glucose readings are in-range or out-of-range using the following color emojis:"
                                )
                                Text("🟢: In-Range")
                                Text("🟠: Above-Range")
                                Text("🔴: Below-Range")
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(
                                    "If \"Display IOB and COB\" is also enabled, \"IOB\" and \"COB\" will be replaced with the following emojis:"
                                )
                                Text("💉: IOB")
                                Text("🥨: COB")
                            }
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.displayCalendarIOBandCOB,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Display IOB and COB")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Display IOB and COB"),
                        miniHint: String(localized: "Include IOB & COB in the calendar event data."),
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "When enabled, Trio will include the current IOB and COB values, along with the current glucose reading, in each calendar event created."
                            )
                        }
                    )
                } else if state.useCalendar {
                    if #available(iOS 17.0, *) {
                        Text(
                            "If you are not seeing calendars to choose here, please go to Settings -> Trio -> Calendars and change permissions to \"Full Access\""
                        ).font(.footnote)

                        Button("Open Settings") {
                            // Get the settings URL and open it
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
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
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Calendar Events")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

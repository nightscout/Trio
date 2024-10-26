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
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useCalendar,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Create Events in Calendar"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Create Events in Calendar",
                    miniHint: """
                    When enabled, Trio creates customizable calendar events in an iCloud calendar'
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        When enabled, Trio will create a calendar event with every successful loop cycle. The previous calendar event will be deleted.

                        You can customize this with the calendar of your choosing, emojis, and IOB/COB.
                        """)
                    },
                    headerText: "Diabetes Data as Calendar Event"
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
                                hintLabel = "Display Emojis as Labels"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Display Emojis as Labels",
                        miniHint: """
                        Enable to use emojis instead of "IOB" or "COB" and to indicate in-range and out-of-range glucose readings
                        Default: OFF
                        """,
                        verboseHint: VStack {
                            Text("Default: OFF").bold()
                            Text("""

                             When enabled, the calendar event created will indicate whether glucose readings are in-range or out-of-range using the following color emojis:
                            🟢: In-Range
                            🟠: Above-Range
                            🔴: Below-Range    

                            If "Display IOB and COB" is also enabled, "IOB" and "COB" will be replaced with the following emojis:
                            💉: IOB
                            🥨: COB
                            """)
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
                                hintLabel = "Display IOB and COB"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Display IOB and COB",
                        miniHint: """
                        Include IOB and COB in the calendar event created by Trio
                        Default: OFF
                        """,
                        verboseHint: VStack {
                            Text("Default: OFF").bold()
                            Text("""

                            When enabled, Trio will include the current IOB and COB values in the calendar event created.
                            """)
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
            .navigationTitle("Calendar Events")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

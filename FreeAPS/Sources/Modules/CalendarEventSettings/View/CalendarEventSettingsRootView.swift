import SwiftUI
import Swinject

extension CalendarEventSettings {
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
                            selectedVerboseHint = $0
                            hintLabel = "Create Events in Calendar"
                        }
                    ),
                    type: .boolean,
                    label: "Create Events in Calendar",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Create Calendar Events… bla bla bla",
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
                                selectedVerboseHint = $0
                                hintLabel = "Display Emojis as Labels"
                            }
                        ),
                        type: .boolean,
                        label: "Display Emojis as Labels",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Display Emojis as Labels… bla bla bla"
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.displayCalendarIOBandCOB,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Display IOB and COB"
                            }
                        ),
                        type: .boolean,
                        label: "Display IOB and COB",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Display IOB and COB… bla bla bla"
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
                    hintText: selectedVerboseHint ?? "",
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

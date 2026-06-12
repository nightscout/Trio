import SwiftUI
import Swinject

extension AlarmWindows {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @StateObject private var store = GlucoseAlertsStore.shared

        @State private var shouldDisplayHint: Bool = false
        @State private var hintDetent = PresentationDetent.large
        @State private var selectedVerboseHint: AnyView?
        @State private var hintLabel: String?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var dayStart: Binding<Date> {
            Binding(
                get: { Self.dateFromTimeOfDay(store.configuration.dayStart) },
                set: { store.configuration.dayStart = Self.timeOfDay(from: $0) }
            )
        }

        private var nightStart: Binding<Date> {
            Binding(
                get: { Self.dateFromTimeOfDay(store.configuration.nightStart) },
                set: { store.configuration.nightStart = Self.timeOfDay(from: $0) }
            )
        }

        var body: some View {
            List {
                Section(header: Text("Window Boundaries")) {
                    VStack {
                        DatePicker(
                            selection: dayStart,
                            displayedComponents: .hourAndMinute
                        ) {
                            HStack {
                                Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                                Text("Day Starts")
                            }
                        }
                        .padding(.top)

                        DatePicker(
                            selection: nightStart,
                            displayedComponents: .hourAndMinute
                        ) {
                            HStack {
                                Image(systemName: "moon.stars.fill").foregroundStyle(.indigo)
                                Text("Night Starts")
                            }
                        }

                        HStack(alignment: .center) {
                            Text("Decides when each alarm's Day or Night setting applies.")
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Day and Night Window")
                                    selectedVerboseHint = AnyView(
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text("Default: Day starts 06:00, Night starts 22:00.").bold()
                                            Text(
                                                "These two times define the Day and Night windows. Each alarm's Active setting picks one — Day & Night, Day only, or Night only — and only fires when that window is current."
                                            )
                                            Text(
                                                "The Night window runs from 'Night Starts' back around to 'Day Starts' — so by default, Night covers 22:00 through 06:00 the next morning."
                                            )
                                            Text(
                                                "These windows are shared between Glucose Alarms and Device Alarms."
                                            )
                                        }
                                    )
                                    shouldDisplayHint.toggle()
                                },
                                label: { Image(systemName: "questionmark.circle") }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Day & Night Windows")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help")
                )
            }
            .onAppear(perform: configureView)
        }

        private static func dateFromTimeOfDay(_ time: TimeOfDay) -> Date {
            Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
        }

        private static func timeOfDay(from date: Date) -> TimeOfDay {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        }
    }
}

import Charts
import SwiftUI
import Swinject

extension ISFEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var editMode = EditMode.inactive

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.timeStyle = .short
            return formatter
        }

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

                Group {
                    HStack {
                        HStack {
                            if state.shouldDisplaySaving {
                                ProgressView().padding(.trailing, 10)
                            }

                            Button {
                                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                                impactHeavy.impactOccurred()
                                state.save()

                                // deactivate saving display after 1.25 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                                    state.shouldDisplaySaving = false
                                }
                            } label: {
                                HStack {
                                    if state.shouldDisplaySaving {
                                        ProgressView().padding(.trailing, 10)
                                    }
                                    Text(state.shouldDisplaySaving ? "Saving..." : "Save")
                                }
                                .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                                .padding(10)
                            }
                        }
                        .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                        .disabled(shouldDisableButton)
                        .background(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
                        .tint(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        var body: some View {
            Form {
                if !state.canAdd {
                    Section {
                        VStack(alignment: .leading) {
                            Text(
                                "Insulin Sensitivities cover 24 hours. You cannot add more rates. Please remove or adjust existing rates to make space."
                            ).bold()
                        }
                    }.listRowBackground(Color.tabBar)
                }

                Section(header: Text("Schedule")) {
                    list
                }.listRowBackground(Color.chart)

                Section {} header: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "note.text.badge.plus").foregroundStyle(.primary)
                            Text("Add an entry by tapping 'Add Sensitivity +' in the top right-hand corner of the screen.")
                        }
                        HStack {
                            Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                            Text("Swipe left to delete a single entry. Tap on it, to edit its time or rate.")
                        }
                    }
                    .textCase(nil)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 30) { saveButton }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Insulin Sensitivities")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { state.add() }) {
                        HStack {
                            Text("Add Sensitivity")
                            Image(systemName: "plus")
                        }
                    }.disabled(!state.canAdd)
                }
            })
            .environment(\.editMode, $editMode)
            .onAppear {
                state.validate()
            }
        }

        private func pickers(for index: Int) -> some View {
            Form {
                Section {
                    Picker(selection: $state.items[index].rateIndex, label: Text("Rate")) {
                        ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                            Text(
                                state.units == .mgdL ? state.rateValues[i].description : state.rateValues[i]
                                    .formattedAsMmolL + String(localized: " \(state.units.rawValue)/U")
                            ).tag(i)
                        }
                    }
                }.listRowBackground(Color.chart)

                Section {
                    Picker(selection: $state.items[index].timeIndex, label: Text("Time")) {
                        ForEach(0 ..< state.timeValues.count, id: \.self) { i in
                            Text(
                                self.dateFormatter
                                    .string(from: Date(
                                        timeIntervalSince1970: state
                                            .timeValues[i]
                                    ))
                            ).tag(i)
                        }
                    }
                }.listRowBackground(Color.chart)
            }
            .padding(.top)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Set Rate")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private var list: some View {
            List {
                chart.padding(.vertical)
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    let displayValue = state.units == .mgdL ? state.rateValues[item.rateIndex].description : state
                        .rateValues[item.rateIndex].formattedAsMmolL

                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text("Rate").foregroundColor(.secondary)

                            Text(
                                displayValue + String(localized: " \(state.units.rawValue)/U")
                            )
                            Spacer()
                            Text("starts at").foregroundColor(.secondary)
                            Text(
                                "\(dateFormatter.string(from: Date(timeIntervalSince1970: state.timeValues[item.timeIndex])))"
                            )
                        }
                    }
                    .moveDisabled(true)
                }
                .onDelete(perform: onDelete)
            }
        }

        var now = Date()

        var chart: some View {
            Chart {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    let displayValue = state.units == .mgdL ? state.rateValues[item.rateIndex].description : state
                        .rateValues[item.rateIndex].formattedAsMmolL

                    // Convert from string so we know we use the same math as the rest of Trio.
                    // However, swift doesn't understand languages that use comma as decimal delminator
                    let displayValueFloat = Double(displayValue.replacingOccurrences(of: ",", with: "."))

                    let startDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(state.timeValues[item.timeIndex])

                    let endDate = state.items
                        .count > index + 1 ?
                        Calendar.current.startOfDay(for: now)
                        .addingTimeInterval(state.timeValues[state.items[index + 1].timeIndex])
                        :
                        Calendar.current.startOfDay(for: now)
                        .addingTimeInterval(state.timeValues.last! + 30 * 60)
                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", displayValueFloat ?? 0),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                Color.cyan.opacity(0.6),
                                Color.cyan.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("ISF", displayValueFloat ?? 0))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.cyan)

                    LineMark(x: .value("Start Date", endDate), y: .value("ISF", displayValueFloat ?? 0))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.cyan)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: now) ... Calendar
                    .current.startOfDay(for: now)
                    .addingTimeInterval(60 * 60 * 24)
            )
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
            state.validate()
        }
    }
}

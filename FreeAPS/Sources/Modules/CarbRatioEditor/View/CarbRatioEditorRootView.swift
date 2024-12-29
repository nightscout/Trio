import Charts
import SwiftUI
import Swinject

extension CarbRatioEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var editMode = EditMode.inactive

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.timeStyle = .short
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.shouldDisplaySaving || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

                Group {
                    HStack {
                        HStack {
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
                                }.padding(10)
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
                if let autotune = state.autotune, !state.settingsManager.settings.onlyAutotuneBasals {
                    Section(header: Text("Autotune")) {
                        HStack {
                            Text("Calculated Ratio")
                            Spacer()
                            Text(rateFormatter.string(from: autotune.carbRatio as NSNumber) ?? "0")
                            Text("g/U").foregroundColor(.secondary)
                        }
                    }.listRowBackground(Color.chart)
                }

                if !state.canAdd {
                    Section {
                        VStack(alignment: .leading) {
                            Text(
                                "Carb Ratios cover 24 hours. You cannot add more rates. Please remove or adjust existing rates to make space."
                            ).bold()
                        }
                    }.listRowBackground(Color.tabBar)
                }

                Section(header: Text("Schedule")) {
                    list
                }.listRowBackground(Color.chart)
            }
            .safeAreaInset(edge: .bottom, spacing: 30) { saveButton }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Carb Ratios")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar(content: {
                if state.items.isNotEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { state.add() }) { Image(systemName: "plus") }.disabled(!state.canAdd)
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
                    Picker(selection: $state.items[index].rateIndex, label: Text("Ratio")) {
                        ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                            Text(
                                (
                                    self.rateFormatter
                                        .string(from: state.rateValues[i] as NSNumber) ?? ""
                                ) + " g/U"
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
            .navigationTitle("Set Ratio")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private var list: some View {
            List {
                chart.padding(.vertical)
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text("Ratio").foregroundColor(.secondary)
                            Text(
                                "\(rateFormatter.string(from: state.rateValues[item.rateIndex] as NSNumber) ?? "0") g/U"
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

        let chartScale = Calendar.current
            .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))

        var chart: some View {
            Chart {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    let displayValue = state.rateValues[item.rateIndex]

                    let tzOffset = TimeZone.current.secondsFromGMT() * -1
                    let startDate = Date(timeIntervalSinceReferenceDate: state.timeValues[item.timeIndex])
                        .addingTimeInterval(TimeInterval(tzOffset))
                    let endDate = state.items
                        .count > index + 1 ?
                        Date(timeIntervalSinceReferenceDate: state.timeValues[state.items[index + 1].timeIndex])
                        .addingTimeInterval(TimeInterval(tzOffset)) :
                        Date(timeIntervalSinceReferenceDate: state.timeValues.last!).addingTimeInterval(30 * 60)
                        .addingTimeInterval(TimeInterval(tzOffset))
                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", displayValue),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                Color.insulin.opacity(0.6),
                                Color.insulin.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("Ratio", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                    LineMark(x: .value("Start Date", endDate), y: .value("Ratio", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: chartScale!) ... Calendar.current.startOfDay(for: chartScale!)
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

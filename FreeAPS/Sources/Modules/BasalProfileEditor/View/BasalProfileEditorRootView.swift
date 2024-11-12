import Charts
import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var editMode = EditMode.inactive

        let chartScale = Calendar.current
            .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))

        @Environment(\.colorScheme) var colorScheme
        var color: LinearGradient {
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

        var basalScheduleChart: some View {
            Chart {
                ForEach(state.chartData!, id: \.self) { profile in
                    RectangleMark(
                        xStart: .value("start", profile.startDate),
                        xEnd: .value("end", profile.endDate!),
                        yStart: .value("rate-start", profile.amount),
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

                    LineMark(x: .value("End Date", profile.endDate!), y: .value("Amount", profile.amount))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                    LineMark(x: .value("Start Date", profile.startDate), y: .value("Amount", profile.amount))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 2)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: chartScale!) ... Calendar.current.startOfDay(for: chartScale!)
                    .addingTimeInterval(60 * 60 * 24)
            )
        }

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.syncInProgress || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(Color.chart)
                Group {
                    HStack {
                        Button {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()
                        } label: {
                            HStack {
                                if state.syncInProgress {
                                    ProgressView().padding(.trailing, 10)
                                }
                                Text(state.syncInProgress ? "Saving..." : "Save")
                            }.padding(10)
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
                Section(header: Text("Schedule")) {
                    if !state.items.isEmpty {
                        basalScheduleChart.padding(.vertical)
                    }

                    list
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Text("Total")
                            .bold()
                            .foregroundColor(.primary)
                        Spacer()
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                            .foregroundColor(.primary) +
                            Text(" U/day")
                            .foregroundColor(.secondary)
                    }
                }.listRowBackground(Color.chart)
            }
            .safeAreaInset(edge: .bottom, spacing: 30) { saveButton }
            .alert(isPresented: $state.showAlert) {
                Alert(
                    title: Text("Unable to Save"),
                    message: Text("Trio could not communicate with your pump. Changes to your basal profile were not saved."),
                    dismissButton: .default(Text("Close"))
                )
            }
            .onChange(of: state.items) {
                state.calcTotal()
                state.caluclateChartData()
            }
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("Basal Profile")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addButton
                }
            })
            .environment(\.editMode, $editMode)
            .onAppear {
                configureView()
                state.validate()
                state.caluclateChartData()
            }
        }

        private func pickers(for index: Int) -> some View {
            Form {
                Section {
                    Picker(selection: $state.items[index].rateIndex, label: Text("Rate")) {
                        ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                            Text(
                                (
                                    self.rateFormatter
                                        .string(from: state.rateValues[i] as NSNumber) ?? ""
                                ) + " U/hr"
                            ).tag(i)
                        }
                    }
                    .onChange(of: state.items[index].rateIndex, { state.calcTotal() })
                }.listRowBackground(Color.chart)

                Section {
                    Picker(selection: $state.items[index].timeIndex, label: Text("Time")) {
                        ForEach(state.availableTimeIndices(index), id: \.self) { i in
                            Text(
                                self.dateFormatter
                                    .string(from: Date(
                                        timeIntervalSince1970: state
                                            .timeValues[i]
                                    ))
                            ).tag(i)
                        }
                    }
                    .onChange(of: state.items[index].timeIndex, { state.calcTotal() })
                }.listRowBackground(Color.chart)
            }
            .padding(.top)
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("Set Rate")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text("Rate").foregroundColor(.secondary)
                            Text(
                                "\(rateFormatter.string(from: state.rateValues[item.rateIndex] as NSNumber) ?? "0") U/hr"
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

        private var addButton: some View {
            guard state.canAdd else {
                return AnyView(EmptyView())
            }

            switch editMode {
            case .inactive:
                return AnyView(Button(action: onAdd) { Image(systemName: "plus") })
            default:
                return AnyView(EmptyView())
            }
        }

        func onAdd() {
            state.add()
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
            state.validate()
            state.calcTotal()
            state.caluclateChartData()
        }
    }
}

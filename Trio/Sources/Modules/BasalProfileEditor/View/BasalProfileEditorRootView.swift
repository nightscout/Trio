import Charts
import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var refreshUI = UUID()
        @State private var now = Date()
        @Namespace private var bottomID

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        // Chart for visualizing basal profile
        private var basalProfileChart: some View {
            Chart {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    let displayValue = state.rateValues[item.rateIndex]

                    let startDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(state.timeValues[item.timeIndex])

                    var offset: TimeInterval {
                        if state.items.count > index + 1 {
                            return state.timeValues[state.items[index + 1].timeIndex]
                        } else {
                            return state.timeValues.last! + 30 * 60
                        }
                    }

                    let endDate = Calendar.current.startOfDay(for: now).addingTimeInterval(offset)

                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", displayValue),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                Color.purple.opacity(0.6),
                                Color.purple.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("Rate", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.purple)

                    LineMark(x: .value("Start Date", endDate), y: .value("Rate", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.purple)
                }
            }
            .id(refreshUI) // Force chart update
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: now) ... Calendar.current.startOfDay(for: now)
                    .addingTimeInterval(60 * 60 * 24)
            )
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
        }

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.syncInProgress || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

                Group {
                    HStack {
                        Button(action: {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()
                        }, label: {
                            HStack {
                                if state.syncInProgress {
                                    ProgressView().padding(.trailing, 10)
                                }
                                Text(state.syncInProgress ? "Saving..." : "Save")
                            }
                            .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                            .padding(10)
                        })
                            .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                            .disabled(shouldDisableButton)
                            .background(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
                            .tint(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        var fullScheduleWarning: some View {
            VStack {
                Text(
                    "Basal profile covers 24 hours. You cannot add more rates. Please remove or adjust existing rates to make space."
                ).bold()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.tabBar)
            .clipShape(
                .rect(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 10
                )
            )
        }

        var totalBasalRow: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Total")
                        .bold()

                    Spacer()

                    HStack {
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                        Text("U/day")
                            .foregroundStyle(Color.secondary)
                    }
                    .id(refreshUI)
                }
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
            .padding(.horizontal)
            .id(bottomID)
        }

        var body: some View {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack {
                            VStack(alignment: .leading, spacing: 0) {
                                if !state.canAdd {
                                    fullScheduleWarning
                                        .padding()
                                }

                                // Chart visualization
                                if !state.items.isEmpty {
                                    basalProfileChart
                                        .frame(height: 180)
                                        .padding()
                                        .background(Color.chart.opacity(0.65))
                                        .clipShape(
                                            .rect(
                                                topLeadingRadius: 10,
                                                bottomLeadingRadius: 0,
                                                bottomTrailingRadius: 0,
                                                topTrailingRadius: 10
                                            )
                                        )
                                        .padding(.horizontal)
                                        .padding(.top)
                                }

                                // Basal profile list
                                TherapySettingEditorView(
                                    items: $state.therapyItems,
                                    unit: .unitPerHour,
                                    timeOptions: state.timeValues,
                                    valueOptions: state.rateValues,
                                    validateOnDelete: state.validate,
                                    onItemAdded: {
                                        withAnimation {
                                            proxy.scrollTo(bottomID, anchor: .bottom)
                                        }
                                    }
                                )
                                .padding(.horizontal)

                                if !state.items.isEmpty {
                                    totalBasalRow
                                }

                                HStack {
                                    Image(systemName: "hand.draw.fill")
                                        .padding(.leading)

                                    Text("Swipe to delete a single entry. Tap on it, to edit its time or value.")
                                        .padding(.trailing)
                                }
                                .font(.subheadline)
                                .fontWeight(.light)
                                .foregroundStyle(.secondary)
                                .padding()
                            }
                        }
                    }

                    saveButton
                }
                .background(appState.trioBackgroundColor(for: colorScheme))
                .alert(isPresented: $state.showAlert) {
                    Alert(
                        title: Text("Unable to Save"),
                        message: Text("Trio could not communicate with your pump. Changes to your basal profile were not saved."),
                        dismissButton: .default(Text("Close"))
                    )
                }
                .navigationTitle("Basal Rates")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear {
                    configureView()
                    state.validate()
                    state.therapyItems = state.getTherapyItems()
                }
                .onChange(of: state.therapyItems) { _, newItems in
                    state.updateFromTherapyItems(newItems)
                    state.calcTotal()
                    refreshUI = UUID()
                }
            }
        }
    }
}

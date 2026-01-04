import Charts
import SwiftUI
import Swinject

extension CarbRatioEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var refreshUI = UUID()
        @State private var now = Date()
        @Namespace private var bottomID

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
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
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack {
                            VStack(alignment: .leading, spacing: 0) {
                                // Chart visualization
                                if !state.items.isEmpty {
                                    carbRatioChart
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

                                // Carb ratio list
                                TherapySettingEditorView(
                                    items: $state.therapyItems,
                                    unit: .gramPerUnit,
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
                .onAppear(perform: configureView)
                .navigationTitle("Carb Ratios")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear {
                    state.validate()
                    state.therapyItems = state.getTherapyItems()
                }
                .onChange(of: state.therapyItems) { _, newItems in
                    state.updateFromTherapyItems(newItems)
                    refreshUI = UUID()
                }
            }
        }

        // Chart for visualizing carb ratios
        private var carbRatioChart: some View {
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
                                Color.orange.opacity(0.6),
                                Color.orange.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("Ratio", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.orange)

                    LineMark(x: .value("Start Date", endDate), y: .value("Ratio", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.orange)
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
    }
}

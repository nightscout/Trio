import Charts
import SwiftDate
import SwiftUI
import Swinject

extension Stat {
    struct RootView: BaseView {
        enum Constants {
            static let spacing: CGFloat = 16
            static let cornerRadius: CGFloat = 10
            static let backgroundOpacity = 0.1
        }

        let resolver: Resolver
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State var state = StateModel()
        @State private var selectedView: ViewType = .statistics
        @State private var selectedChartType: ChartType = .percentile

        enum ViewType: String, CaseIterable, Identifiable {
            case statistics = "Time in Range"
            case tdd = "Total Daily Doses"
            case loops = "Loop Stats"
            case meals = "Meal Stats"

            var id: String { rawValue }
            var title: String {
                switch self {
                case .statistics: return NSLocalizedString("Time in Range", comment: "Statistics view title")
                case .tdd: return NSLocalizedString("Total Daily Doses", comment: "TDD view title")
                case .loops: return NSLocalizedString("Loop Stats", comment: "Loop stats view title")
                case .meals: return NSLocalizedString("Meal Stats", comment: "Meal stats view title")
                }
            }
        }

        enum ChartType: String, CaseIterable {
            case percentile = "Percentile"
            case stacked = "Distribution"
        }

        var body: some View {
            VStack(spacing: Constants.spacing) {
                segmentedPicker

                contentView
                    .animation(.easeInOut, value: selectedView)
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    closeButton
                }
            }
        }

        // MARK: - Views

        private var segmentedPicker: some View {
            Picker("View", selection: $selectedView) {
                ForEach(ViewType.allCases) { viewType in
                    Text(viewType.title).tag(viewType)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }

        @ViewBuilder private var contentView: some View {
            switch selectedView {
            case .statistics:
                statsView()
            case .tdd:
                tddView()
            case .loops:
                loopsView()
            case .meals:
                mealsView()
            }
        }

        private var closeButton: some View {
            Button(action: state.hideModal) {
                Text("Close")
                    .foregroundColor(.tabBar)
            }
        }

        // MARK: - Stats View

        @ViewBuilder func statsView() -> some View {
            ScrollView {
                VStack(spacing: Constants.spacing) {
                    if state.glucoseFromPersistence.isEmpty {
                        ContentUnavailableView(
                            "No Glucose Data",
                            systemImage: "chart.bar.fill",
                            description: Text("Glucose statistics will appear here once data is available.")
                        )
                    } else {
                        timeInRangeCard
                        glucoseStatsCard
                    }
                }
                .padding()
            }
        }

        @ViewBuilder func tddView() -> some View {
            ScrollView {
                VStack(spacing: Constants.spacing) {
                    TDDChartView(
                        state: state,
                        selectedDays: $state.requestedDaysTDD,
                        selectedEndDate: $state.requestedEndDayTDD,
                        dailyTotalDoses: $state.dailyTotalDoses,
                        averageTDD: state.averageTDD,
                        ytdTDD: state.ytdTDDValue
                    )
                    .onChange(of: state.requestedDaysTDD) {
                        state.updateBolusStats()
                    }
                    .onChange(of: state.requestedEndDayTDD) {
                        state.updateBolusStats()
                    }

                    BolusStatsView(
                        bolusStats: state.bolusStats,
                        selectedDays: $state.requestedDaysTDD,
                        selectedEndDate: $state.requestedEndDayTDD
                    )
                }
                .padding()
            }
        }

        @ViewBuilder func loopsView() -> some View {
            ScrollView {
                VStack(spacing: Constants.spacing) {
                    if state.loopStatRecords.isEmpty {
                        ContentUnavailableView(
                            "No Loop Data",
                            systemImage: "clock.arrow.2.circlepath",
                            description: Text("Loop statistics will appear here once data is available.")
                        )
                    } else {
                        loopsCard
                        loopStats
                    }
                }
                .padding()
            }
        }

        private var timeInRangeCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    HStack {
                        Text("Time in Range")
                            .font(.headline)

                        Spacer()

                        HStack {
                            Picker("Duration", selection: $state.selectedDuration) {
                                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                                    Text(duration.rawValue)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Chart Type", selection: $selectedChartType) {
                                ForEach(ChartType.allCases, id: \.self) { type in
                                    Text(type.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    if selectedChartType == .percentile {
                        GlucoseAreaChart(
                            glucose: state.glucoseFromPersistence,
                            highLimit: state.highLimit,
                            lowLimit: state.lowLimit,
                            isTodayOrLast24h: state.selectedDuration == .Today || state.selectedDuration == .Day,
                            units: state.units,
                            hourlyStats: state.hourlyStats
                        )
                    } else {
                        GlucoseStackedAreaChart(
                            glucose: state.glucoseFromPersistence,
                            highLimit: state.highLimit,
                            lowLimit: state.lowLimit,
                            isToday: state.selectedDuration == .Today || state.selectedDuration == .Day,
                            units: state.units,
                            glucoseRangeStats: state.glucoseRangeStats
                        )
                    }

                    Divider()

                    SectorChart(
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                        timeInRangeChartStyle: state.timeInRangeChartStyle,
                        glucose: state.glucoseFromPersistence
                    )
                }
            }
        }

        private var glucoseStatsCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    BareStatisticsView.HbA1cView(
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                        glucose: state.glucoseFromPersistence
                    )

                    Divider()

                    BareStatisticsView.BloodGlucoseView(
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                        glucose: state.glucoseFromPersistence
                    )
                }
            }
        }

        private var loopsCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    HStack {
                        Text("Loops")
                            .font(.headline)

                        Spacer()

                        Picker("Duration", selection: $state.selectedDurationForLoopStats) {
                            ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                                Text(duration.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    LoopStatsView(
                        loopStatRecords: state.loopStatRecords,
                        selectedDuration: state.selectedDurationForLoopStats,
                        groupedStats: state.groupedLoopStats
                    )
                }
            }
        }

        private var loopStats: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    BareStatisticsView.LoopsView(
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                        loopStatRecords: state.loopStatRecords
                    )
                }
            }
        }

        @ViewBuilder func mealsView() -> some View {
            ScrollView {
                VStack(spacing: Constants.spacing) {
                    Picker("Duration", selection: $state.selectedDurationForMealStats) {
                        ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                            Text(duration.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    MealStatsView(
                        mealStats: state.mealStats,
                        selectedDuration: state.selectedDurationForMealStats
                    )
                }
                .padding()
            }
        }
    }
}

// MARK: - Supporting Views

struct StatCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Stat.RootView.Constants.cornerRadius)
                    .fill(Color.secondary.opacity(Stat.RootView.Constants.backgroundOpacity))
            )
    }
}

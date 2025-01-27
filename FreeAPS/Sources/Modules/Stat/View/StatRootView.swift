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
        @State private var selectedView: StatisticViewType = .glucose
        @State private var selectedGlucoseChartType: GlucoseChartType = .percentile
        @State private var selectedInsulinChartType: InsulinChartType = .totalDailyDose
        @State private var selectedLoopingChartType: LoopingChartType = .loopingPerformance
        @State private var selectedMealChartType: MealChartType = .totalMeals

        enum StatisticViewType: String, CaseIterable, Identifiable {
            case glucose
            case insulin
            case looping
            case meals

            var id: String { rawValue }
            var title: String {
                switch self {
                case .glucose: return "Glucose"
                case .insulin: return "Insulin"
                case .looping: return "Looping"
                case .meals: return "Meals"
                }
            }
        }

        enum GlucoseChartType: String, CaseIterable {
            case percentile = "Percentile"
            case distribution = "Distribution"
        }

        enum InsulinChartType: String, CaseIterable {
            case totalDailyDose = "Total Daily Dose"
            case bolusDistribution = "Bolus Distribution"
        }

        enum LoopingChartType: String, CaseIterable {
            case loopingPerformance = "Looping Performance"
            case cgmConnectionTrace = "CGM Connection Trace"
            case trioUpTime = "Trio Up-Time"
        }

        enum MealChartType: String, CaseIterable {
            case totalMeals = "Total Meals"
            case mealToHypoHyperDistribution = "Meal to Hypo/Hyper"
        }

        var body: some View {
            VStack {
                Picker("View", selection: $selectedView) {
                    ForEach(StatisticViewType.allCases) { viewType in
                        Text(viewType.title).tag(viewType)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: Constants.spacing) {
                        switch selectedView {
                        case .glucose:
                            glucoseView
                        case .insulin:
                            insulinView
                        case .looping:
                            loopingView
                        case .meals:
                            mealsView
                        }
                    }
                    .padding()
                }
//                .animation(.easeInOut, value: selectedView)
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: state.hideModal) {
                        Text("Close")
                            .foregroundColor(.tabBar)
                    }
                }
            }
        }

        // MARK: - Stats View

        @ViewBuilder var glucoseView: some View {
            HStack {
                Text("Chart Type")
                    .font(.headline)

                Spacer()

                Picker("Glucose Chart Type", selection: $selectedGlucoseChartType) {
                    ForEach(GlucoseChartType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedDurationForGlucoseStats) {
                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                    Text(duration.rawValue)
                }
            }
            .pickerStyle(.segmented)

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

        @ViewBuilder var insulinView: some View {
            HStack {
                Text("Chart Type")
                    .font(.headline)

                Spacer()

                Picker("Insulin Chart Type", selection: $selectedInsulinChartType) {
                    ForEach(InsulinChartType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                    }
                }.pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedDurationForInsulinStats) {
                ForEach(StateModel.StatsTimeInterval.allCases) { timeInterval in
                    Text(timeInterval.rawValue).tag(timeInterval)
                }
            }
            .pickerStyle(.segmented)

            switch selectedInsulinChartType {
            case .totalDailyDose:
                if state.tddStats.isEmpty {
                    ContentUnavailableView(
                        "No TDD Data",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Total Daily Doses will appear here once data is available.")
                    )
                } else {
                    TDDChartView(
                        selectedDuration: state.selectedDurationForInsulinStats,
                        tddStats: state.tddStats,
                        calculateAverage: { start, end in
                            state.calculateAverageTDD(from: start, to: end)
                        }
                    )
                }

            case .bolusDistribution:
                var hasBolusData: Bool {
                    state.bolusStats.contains { $0.manualBolus > 0 || $0.smb > 0 || $0.external > 0 }
                }

                if state.bolusStats.isEmpty || !hasBolusData {
                    ContentUnavailableView(
                        "No Bolus Data",
                        systemImage: "cross.vial",
                        description: Text("Bolus statistics will appear here once data is available.")
                    )
                } else {
                    BolusStatsView(
                        bolusStats: state.bolusStats
                    )
                }
            }
        }

        private var timeInRangeCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    switch selectedGlucoseChartType {
                    case .percentile:
                        GlucosePercentileChart(
                            glucose: state.glucoseFromPersistence,
                            highLimit: state.highLimit,
                            lowLimit: state.lowLimit,
                            units: state.units,
                            hourlyStats: state.hourlyStats,
                            isToday: state.selectedDurationForGlucoseStats == .Today
                        )
                    case .distribution:
                        GlucoseDistributionChart(
                            glucose: state.glucoseFromPersistence,
                            highLimit: state.highLimit,
                            lowLimit: state.lowLimit,
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

        @ViewBuilder var loopingView: some View {
            HStack {
                Text("Chart Type")
                    .font(.headline)

                Spacer()

                Picker("Looping Chart Type", selection: $selectedLoopingChartType) {
                    ForEach(LoopingChartType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                    }
                }.pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedDurationForLoopStats) {
                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                    Text(duration.rawValue)
                }
            }
            .pickerStyle(.segmented)

            switch selectedLoopingChartType {
            case .loopingPerformance:
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
            case .trioUpTime:
                Text("Not yet implemented")
            case .cgmConnectionTrace:
                Text("Not yet implemented")
            }
        }

        private var loopsCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
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

        @ViewBuilder var mealsView: some View {
            HStack {
                Text("Chart Type")
                    .font(.headline)

                Spacer()

                Picker("Meal Chart Type", selection: $selectedMealChartType) {
                    ForEach(MealChartType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                    }
                }.pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedDurationForMealStats) {
                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                    Text(duration.rawValue)
                }
            }
            .pickerStyle(.segmented)

            StatCard {
                switch selectedMealChartType {
                case .totalMeals:
                    var hasMealData: Bool {
                        state.mealStats.contains { $0.carbs > 0 || $0.fat > 0 || $0.protein > 0 }
                    }

                    if state.mealStats.isEmpty || !hasMealData {
                        ContentUnavailableView(
                            "No Meal Data",
                            systemImage: "fork.knife",
                            description: Text("Meal statistics will appear here once data is available.")
                        )
                    } else {
                        MealStatsView(
                            mealStats: state.mealStats,
                            selectedDuration: state.selectedDurationForMealStats
                        )
                    }
                case .mealToHypoHyperDistribution:
                    Text("TODO: Meal to Hypoglycemia/Hyperglycemia Distribution")
                }
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

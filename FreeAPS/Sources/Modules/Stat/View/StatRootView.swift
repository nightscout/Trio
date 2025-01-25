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
            case stacked = "Distribution"
        }

        enum InsulinChartType: String, CaseIterable {
            case totalDailyDose = "Total Daily Dose"
            case bolusDistribution = "Bolus Distribution"
        }

        enum LoopingChartType: String, CaseIterable {
            case loopingPerformance = "Looping Performance"
            case trioUpTime = "Trio Up Time"
            case cgmConnectionTrace = "CGM Connection Trace"
        }

        enum MealChartType: String, CaseIterable {
            case totalMeals = "Total Meals"
            case mealToHypoHyperDistribution = "Meal to Hypo/Hyper"
        }

        var body: some View {
            VStack {
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
                ForEach(StatisticViewType.allCases) { viewType in
                    Text(viewType.title).tag(viewType)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }

        @ViewBuilder private var contentView: some View {
            ScrollView {
                VStack(spacing: Constants.spacing) {
                    switch selectedView {
                    case .glucose:
                        glucoseView()
                    case .insulin:
                        insulinView()
                    case .looping:
                        loopingView()
                    case .meals:
                        mealsView()
                    }
                }
                .padding()
            }
        }

        private var closeButton: some View {
            Button(action: state.hideModal) {
                Text("Close")
                    .foregroundColor(.tabBar)
            }
        }

        // MARK: - Stats View

        @ViewBuilder func glucoseView() -> some View {
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

            Picker("Duration", selection: $state.selectedDuration) {
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

        @ViewBuilder func insulinView() -> some View {
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

            Picker("Duration", selection: $state.selectedDuration) {
                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                    Text(duration.rawValue)
                }
            }
            .pickerStyle(.segmented)

            // TODO: rework TDDChartView and BolusView to respect selectedDays from here and omit datepicker
            switch selectedInsulinChartType {
            case .totalDailyDose:
                if state.dailyTotalDoses.isEmpty || state.currentTDD == 0 {
                    ContentUnavailableView(
                        "No TDD Data",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Total Daily Doses will appear here once data is available.")
                    )
                } else {
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
                        bolusStats: state.bolusStats,
                        selectedDays: $state.requestedDaysTDD,
                        selectedEndDate: $state.requestedEndDayTDD
                    )
                }
            }
        }

        private var timeInRangeCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    switch selectedGlucoseChartType {
                    case .percentile:
                        GlucoseAreaChart(
                            glucose: state.glucoseFromPersistence,
                            highLimit: state.highLimit,
                            lowLimit: state.lowLimit,
                            isTodayOrLast24h: state.selectedDuration == .Today || state.selectedDuration == .Day,
                            units: state.units,
                            hourlyStats: state.hourlyStats
                        )
                    case .stacked:
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

        @ViewBuilder func loopingView() -> some View {
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

            Picker("Duration", selection: $state.selectedDuration) {
                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                    Text(duration.rawValue)
                }
            }
            .pickerStyle(.segmented)

            // TODO: ensure looping uses same day selection
//            Picker("Duration", selection: $state.selectedDurationForLoopStats) {
//                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
//                    Text(duration.rawValue)
//                }
//            }
//            .pickerStyle(.menu)

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

        @ViewBuilder func mealsView() -> some View {
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

            Picker("Duration", selection: $state.selectedDuration) {
                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
                    Text(duration.rawValue)
                }
            }
            .pickerStyle(.segmented)

            // TODO: adjust this so all tabs use the same selected days
//            Picker("Duration", selection: $state.selectedDurationForMealStats) {
//                ForEach(StateModel.Duration.allCases, id: \.self) { duration in
//                    Text(duration.rawValue)
//                }
//            }
//            .pickerStyle(.menu)

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

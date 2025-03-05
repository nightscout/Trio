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
        @State private var selectedView: StateModel.StatisticViewType = .glucose

        var body: some View {
            VStack {
                Picker("View", selection: $selectedView) {
                    ForEach(StateModel.StatisticViewType.allCases) { viewType in
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

                Picker("Glucose Chart Type", selection: $state.selectedGlucoseChartType) {
                    ForEach(GlucoseChartType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedDurationForGlucoseStats) {
                ForEach(StateModel.Duration.allCases, id: \.self) { timeInterval in
                    Text(timeInterval.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if state.glucoseFromPersistence.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Glucose Data"),
                    systemImage: "chart.bar.fill",
                    description: Text("Glucose statistics will appear here once data is available.")
                )
            } else {
                timeInRangeCard
                glucoseStatsCard

                HStack {
                    var hintText: String {
                        switch state.selectedGlucoseChartType {
                        case .percentile:
                            String(localized: "Tap and hold the AGP graph or Time-in-Range ring to reveal more details.")
                        case .distribution:
                            String(localized: "Tap and hold the Time-in-Range ring to reveal more details.")
                        }
                    }
                    Image(systemName: "hand.draw.fill")
                        .foregroundStyle(Color.primary)
                        .padding(.leading)
                    Text(hintText)
                        .foregroundStyle(Color.secondary)
                        .padding(.trailing)
                }.font(.footnote)
            }
        }

        private var timeInRangeCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    switch state.selectedGlucoseChartType {
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
                }
            }
        }

        private var glucoseStatsCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    GlucoseSectorChart(
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        glucose: state.glucoseFromPersistence
                    )

                    Divider()

                    GlucoseMetricsView(
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        eA1cDisplayUnit: state.eA1cDisplayUnit,
                        glucose: state.glucoseFromPersistence
                    )
                }
            }
        }

        @ViewBuilder var insulinView: some View {
            HStack {
                Text("Chart Type")
                    .font(.headline)

                Spacer()

                Picker("Insulin Chart Type", selection: $state.selectedInsulinChartType) {
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

            StatCard {
                switch state.selectedInsulinChartType {
                case .totalDailyDose:
                    if state.dailyTDDStats.isEmpty {
                        ContentUnavailableView(
                            String(localized: "No TDD Data"),
                            systemImage: "chart.bar.xaxis",
                            description: Text("Total Daily Doses will appear here once data is available.")
                        )
                    } else {
                        TotalDailyDoseChart(
                            selectedDuration: $state.selectedDurationForInsulinStats,
                            tddStats: state.selectedDurationForInsulinStats == .Day ?
                                state.hourlyTDDStats : state.dailyTDDStats,
                            state: state
                        )
                    }

                case .bolusDistribution:
                    var hasBolusData: Bool {
                        state.dailyBolusStats.contains { $0.manualBolus > 0 || $0.smb > 0 || $0.external > 0 }
                    }

                    if state.dailyBolusStats.isEmpty || !hasBolusData {
                        ContentUnavailableView(
                            String(localized: "No Bolus Data"),
                            systemImage: "cross.vial",
                            description: Text("Bolus statistics will appear here once data is available.")
                        )
                    } else {
                        BolusStatsView(
                            selectedDuration: $state.selectedDurationForInsulinStats,
                            bolusStats: state.selectedDurationForInsulinStats == .Day ?
                                state.hourlyBolusStats : state.dailyBolusStats,
                            state: state
                        )
                    }
                }
            }

            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(Color.primary)
                VStack(alignment: .leading) {
                    Text("Swipe the chart to scroll through time.")
                    Text("Tap and hold a bar to reveal more details.")
                }.foregroundStyle(Color.secondary)
            }.font(.footnote)
        }

        @ViewBuilder var loopingView: some View {
            HStack {
                Text("Chart Type")
                    .font(.headline)

                Spacer()

                Picker("Looping Chart Type", selection: $state.selectedLoopingChartType) {
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

            switch state.selectedLoopingChartType {
            case .loopingPerformance:
                if state.loopStatRecords.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Loop Data"),
                        systemImage: "clock.arrow.2.circlepath",
                        description: Text("Loop statistics will appear here once data is available.")
                    )
                } else {
                    loopsCard
                    loopStats
                }
            case .trioUpTime:
                // TODO: Trio Up-Time Chart
                ContentUnavailableView(
                    String(localized: "Coming soon."),
                    systemImage: "hourglass",
                    description: Text("Trio Up-Time Chart")
                )
            case .cgmConnectionTrace:
                // TODO: CGM Connection Trace Chart
                ContentUnavailableView(
                    String(localized: "Coming soon."),
                    systemImage: "hourglass",
                    description: Text("CGM Connection Trace Chart")
                )
            }
        }

        private var loopsCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    LoopBarChartView(
                        loopStatRecords: state.loopStatRecords,
                        selectedDuration: state.selectedDurationForLoopStats,
                        statsData: state.loopStats
                    )
                }
            }
        }

        private var loopStats: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    LoopStatsView(
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        eA1cDisplayUnit: state.eA1cDisplayUnit,
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

                Picker("Meal Chart Type", selection: $state.selectedMealChartType) {
                    ForEach(MealChartType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                    }
                }.pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedDurationForMealStats) {
                ForEach(StateModel.StatsTimeInterval.allCases, id: \.self) { timeInterval in
                    Text(timeInterval.rawValue)
                }
            }
            .pickerStyle(.segmented)

            StatCard {
                switch state.selectedMealChartType {
                case .totalMeals:
                    var hasMealData: Bool {
                        state.dailyMealStats.contains { $0.carbs > 0 || $0.fat > 0 || $0.protein > 0 }
                    }

                    if state.dailyMealStats.isEmpty || !hasMealData {
                        ContentUnavailableView(
                            String(localized: "No Meal Data"),
                            systemImage: "fork.knife",
                            description: Text("Meal statistics will appear here once data is available.")
                        )
                    } else {
                        MealStatsView(
                            selectedDuration: $state.selectedDurationForMealStats,
                            mealStats: state.selectedDurationForMealStats == .Day ?
                                state.hourlyMealStats : state.dailyMealStats,
                            state: state
                        )
                    }
                case .mealToHypoHyperDistribution:
                    // TODO: Meal to Hypoglycemia/Hyperglycemia Distribution
                    ContentUnavailableView(
                        String(localized: "Coming soon."),
                        systemImage: "hourglass",
                        description: Text("Meal to Hypoglycemia/Hyperglycemia Distribution Chart")
                    )
                }
            }

            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(Color.primary)
                VStack(alignment: .leading) {
                    Text("Swipe the chart to scroll through time.")
                    Text("Tap and hold a bar to reveal more details.")
                }.foregroundStyle(Color.secondary)
            }.font(.footnote)
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

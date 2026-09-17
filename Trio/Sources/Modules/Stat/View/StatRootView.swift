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
        @State private var isGlucoseDaySelected: Bool = false
        @State private var showDayPickerSheet = false

        private var intervalOptions: [Stat.StateModel.StatsTimeIntervalWithToday] {
            state.selectedGlucoseChartType == .percentileByDay || state.selectedGlucoseChartType == .distributionByDay
                ? [.week, .month, .total] : Stat.StateModel.StatsTimeIntervalWithToday.allCases
        }

        var body: some View {
            VStack {
                Picker("View", selection: $selectedView) {
                    ForEach(StateModel.StatisticViewType.allCases) { viewType in
                        Text(viewType.displayName).tag(viewType)
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
            // Dense charts and stat grids shatter at accessibility sizes; cap tighter than the global bound.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .sheet(isPresented: $showDayPickerSheet) {
                dayPickerSheet
            }
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

        // MARK: - Day picker

        /// Chooses which calendar day the `.today` interval reports on. Shown only while that
        /// interval is selected, since it means nothing for the rolling windows.
        ///
        /// Chevrons for the common move — a day either side — and a tap on the date for a jump.
        /// Both ends are bounded: there is no data past the stats screen's own three-month
        /// horizon, and none in the future.
        @ViewBuilder private func dayPicker(isVisible: Bool) -> some View {
            if isVisible {
                HStack {
                    Button {
                        shiftSelectedDay(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canShiftSelectedDay(by: -1))
                    .accessibilityLabel(Text("Previous day"))

                    Spacer()

                    Button {
                        showDayPickerSheet = true
                    } label: {
                        Text(selectedDayLabel)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel(Text("Select day, \(selectedDayLabel)"))

                    Spacer()

                    Button {
                        shiftSelectedDay(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canShiftSelectedDay(by: 1))
                    .accessibilityLabel(Text("Next day"))
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 4)
            }
        }

        /// "Today" and "Yesterday" rather than their dates: on the two days people look at most,
        /// the name answers "which day is this?" faster than a date does.
        private var selectedDayLabel: String {
            let calendar = Calendar.current
            if calendar.isDateInToday(state.selectedStatsDay) {
                return String(localized: "Today", comment: "Stats day picker: the current day")
            }
            if calendar.isDateInYesterday(state.selectedStatsDay) {
                return String(localized: "Yesterday", comment: "Stats day picker: the previous day")
            }
            return state.selectedStatsDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }

        private func shiftedDay(by days: Int) -> Date? {
            Calendar.current.date(byAdding: .day, value: days, to: state.selectedStatsDay)
        }

        private func canShiftSelectedDay(by days: Int) -> Bool {
            guard let shifted = shiftedDay(by: days) else { return false }
            let calendar = Calendar.current
            return shifted >= calendar.startOfDay(for: state.earliestSelectableStatsDay)
                && shifted <= calendar.startOfDay(for: Date())
        }

        private func shiftSelectedDay(by days: Int) {
            guard canShiftSelectedDay(by: days), let shifted = shiftedDay(by: days) else { return }
            state.selectedStatsDay = Calendar.current.startOfDay(for: shifted)
        }

        /// Calendar jump for a day further off than a chevron or two. Bounded to the range the
        /// stats screen holds data for, so the calendar cannot land on a day with nothing in it.
        @ViewBuilder private var dayPickerSheet: some View {
            NavigationStack {
                DatePicker(
                    "Day",
                    selection: Binding(
                        get: { state.selectedStatsDay },
                        set: { state.selectedStatsDay = Calendar.current.startOfDay(for: $0) }
                    ),
                    in: Calendar.current.startOfDay(for: state.earliestSelectableStatsDay) ...
                        Calendar.current.startOfDay(for: Date()),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Select Day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Today") {
                            state.selectedStatsDay = Calendar.current.startOfDay(for: Date())
                            showDayPickerSheet = false
                        }
                        .disabled(Calendar.current.isDateInToday(state.selectedStatsDay))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDayPickerSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }

        // MARK: - Stats View

        @ViewBuilder var glucoseView: some View {
            HStack {
                Text("Chart Type")
                    .font(.headline)

                Spacer()

                Picker("Glucose Chart Type", selection: $state.selectedGlucoseChartType) {
                    ForEach(StateModel.GlucoseChartType.allCases, id: \.self) { type in
                        Text(type.displayName)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: state.selectedGlucoseChartType) { _, newValue in
                    // If switching to daily chart and day/today is selected, switch to week
                    if newValue == .percentileByDay || newValue == .distributionByDay,
                       state.selectedIntervalForGlucoseStats == .day || state.selectedIntervalForGlucoseStats == .today
                    {
                        state.selectedIntervalForGlucoseStats = .week
                    }
                }
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedIntervalForGlucoseStats) {
                ForEach(intervalOptions, id: \.self) { timeInterval in
                    Text(timeInterval.displayName)
                }
            }
            .pickerStyle(.segmented)

            dayPicker(isVisible: state.selectedIntervalForGlucoseStats == .today)

            if state.glucoseFromPersistence.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Glucose Data"),
                    systemImage: "chart.bar.fill",
                    description: Text("Glucose statistics will appear here once data is available.")
                )
            } else {
                timeInRangeCard

                if !isGlucoseDaySelected && state.selectedGlucoseChartType != .percentileByDay && state
                    .selectedGlucoseChartType != .distributionByDay
                {
                    glucoseStatsCard
                }

                HStack {
                    var hintText: String {
                        switch state.selectedGlucoseChartType {
                        case .percentileByTime:
                            String(localized: "Tap and hold the AGP graph or Time-in-Range ring to reveal more details.")
                        case .distributionByTime:
                            String(localized: "Tap and hold the Time-in-Range ring to reveal more details.")
                        case .percentileByDay:
                            String(
                                localized: "Tap a percentile or tap and hold a bar to reveal more details. Swipe to scroll through time."
                            )
                        case .distributionByDay:
                            String(
                                localized: "Tap and hold a bar in the chart to reveal more details. Swipe to scroll through time."
                            )
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
                    case .distributionByDay,
                         .percentileByDay:
                        let interval: Stat.StateModel.StatsTimeInterval = {
                            switch state.selectedIntervalForGlucoseStats {
                            case .month,
                                 .total:
                                return Stat.StateModel.StatsTimeInterval(
                                    rawValue: state.selectedIntervalForGlucoseStats.rawValue
                                )!
                            default:
                                return .week
                            }
                        }()

                        if state.selectedGlucoseChartType == .percentileByDay {
                            GlucoseDailyPercentileChart(
                                glucose: state.glucoseFromPersistence,
                                highLimit: state.highLimit,
                                units: state.units,
                                timeInRangeType: state.timeInRangeType,
                                selectedInterval: interval,
                                isDaySelected: $isGlucoseDaySelected,
                                state: state
                            )
                        } else { // if state.selectedGlucoseChartType == .distributionByDay
                            GlucoseDailyDistributionChart(
                                glucose: state.glucoseReadings,
                                highLimit: state.highLimit,
                                units: state.units,
                                timeInRangeType: state.timeInRangeType,
                                selectedInterval: interval,
                                eA1cDisplayUnit: state.eA1cDisplayUnit,
                                isDaySelected: $isGlucoseDaySelected,
                                state: state
                            )
                        }

                    case .percentileByTime:
                        GlucosePercentileChart(
                            glucose: state.glucoseFromPersistence,
                            highLimit: state.highLimit,
                            timeInRangeType: state.timeInRangeType,
                            units: state.units,
                            hourlyStats: state.hourlyStats,
                            isToday: state.selectedIntervalForGlucoseStats == .today
                        )

                    case .distributionByTime:
                        GlucoseDistributionChart(
                            glucose: state.glucoseReadings,
                            highLimit: state.highLimit,
                            lowLimit: state.lowLimit,
                            units: state.units,
                            glucoseRangeStats: state.glucoseRangeStats,
                            timeInRangeType: state.timeInRangeType
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
                        units: state.units,
                        glucose: state.glucoseFromPersistence,
                        timeInRangeType: state.timeInRangeType,
                        showChart: true
                    )

                    Divider()

                    GlucoseMetricsView(
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
                    ForEach(StateModel.InsulinChartType.allCases, id: \.self) { type in
                        Text(type.displayName)
                    }
                }.pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedIntervalForInsulinStats) {
                ForEach(StateModel.StatsTimeInterval.allCases) { timeInterval in
                    Text(timeInterval.displayName).tag(timeInterval)
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
                            selectedInterval: $state.selectedIntervalForInsulinStats,
                            tddStats: state.selectedIntervalForInsulinStats == .day ?
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
                            selectedInterval: $state.selectedIntervalForInsulinStats,
                            bolusStats: state.selectedIntervalForInsulinStats == .day ?
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
                    ForEach(StateModel.LoopingChartType.allCases, id: \.self) { type in
                        Text(type.displayName)
                    }
                }.pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedIntervalForLoopStats) {
                ForEach(StateModel.StatsTimeIntervalWithToday.allCases, id: \.self) { interval in
                    Text(interval.displayName)
                }
            }
            .pickerStyle(.segmented)

            dayPicker(isVisible: state.selectedIntervalForLoopStats == .today)

            StatCard {
                switch state.selectedLoopingChartType {
                case .loopingPerformance:
                    if state.loopStatRecords.isEmpty {
                        ContentUnavailableView(
                            String(localized: "No Loop Data"),
                            systemImage: "clock.arrow.2.circlepath",
                            description: Text("Loop statistics will appear here once data is available.")
                        )
                    } else {
                        loopingChartView
                        loopStats
                    }
                case .cgmConnectionTrace,
                     .trioUpTime:
                    // TODO: Trio Up-Time Chart & CGM Connection Trace Chart
                    ContentUnavailableView(
                        String(localized: "Coming soon."),
                        systemImage: "hourglass",
                        description: Text(state.selectedLoopingChartType.displayName)
                    )
                }
            }
        }

        private var loopingChartView: some View {
            VStack(spacing: Constants.spacing) {
                LoopBarChartView(
                    loopStatRecords: state.loopStatRecords,
                    selectedInterval: state.selectedIntervalForLoopStats,
                    statsData: state.loopStats
                )
            }
        }

        private var loopStats: some View {
            VStack(spacing: Constants.spacing) {
                LoopStatsView(
                    statsData: state.loopStats
                )
            }
        }

        @ViewBuilder var mealsView: some View {
            HStack {
                Text("Chart Type")
                    .font(.headline)

                Spacer()

                Picker("Meal Chart Type", selection: $state.selectedMealChartType) {
                    ForEach(StateModel.MealChartType.allCases, id: \.self) { type in
                        Text(type.displayName)
                    }
                }.pickerStyle(.menu)
            }.padding(.horizontal)

            Picker("Duration", selection: $state.selectedIntervalForMealStats) {
                ForEach(StateModel.StatsTimeInterval.allCases, id: \.self) { timeInterval in
                    Text(timeInterval.displayName)
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
                            selectedInterval: $state.selectedIntervalForMealStats,
                            mealStats: state.selectedIntervalForMealStats == .day ?
                                state.hourlyMealStats : state.dailyMealStats,
                            state: state
                        )
                    }
                case .mealToHypoHyperDistribution:
                    // TODO: Meal to Hypoglycemia/Hyperglycemia Distribution
                    ContentUnavailableView(
                        String(localized: "Coming soon."),
                        systemImage: "hourglass",
                        description: Text(state.selectedMealChartType.displayName)
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

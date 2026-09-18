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
            .onChange(of: state.selectedGlucoseChartType) { _, newValue in
                // The by-day charts need more than a single day of data. A picked range of
                // several days qualifies, so only a one-day window has to be left behind.
                guard newValue == .percentileByDay || newValue == .distributionByDay else { return }
                let isSingleDay = state.selectedIntervalForGlucoseStats == .day
                    || (state.selectedIntervalForGlucoseStats == .today && state.selectedStatsRangeDayCount == 1)
                if isSingleDay {
                    state.selectedIntervalForGlucoseStats = .week
                }
            }
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

        // MARK: - Chart type

        /// Chart type is a menu rather than a segmented control: the names are too long to
        /// fit one. It sits at the trailing end of the control row, sharing that row with the
        /// day picker whenever that one is on screen.
        private var chartTypeMenu: some View {
            Menu {
                switch selectedView {
                case .glucose:
                    Picker("Chart Type", selection: $state.selectedGlucoseChartType) {
                        ForEach(StateModel.GlucoseChartType.allCases, id: \.self) { Text($0.displayName) }
                    }
                case .insulin:
                    Picker("Chart Type", selection: $state.selectedInsulinChartType) {
                        ForEach(StateModel.InsulinChartType.allCases, id: \.self) { Text($0.displayName) }
                    }
                case .looping:
                    Picker("Chart Type", selection: $state.selectedLoopingChartType) {
                        ForEach(StateModel.LoopingChartType.allCases, id: \.self) { Text($0.displayName) }
                    }
                case .meals:
                    Picker("Chart Type", selection: $state.selectedMealChartType) {
                        ForEach(StateModel.MealChartType.allCases, id: \.self) { Text($0.displayName) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedChartTypeName)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.subheadline)
                .lineLimit(1)
                .foregroundColor(.tabBar)
            }
            .pickerStyle(.inline)
            .accessibilityLabel(Text("Chart Type"))
            .accessibilityValue(Text(selectedChartTypeName))
        }

        private var selectedChartTypeName: String {
            switch selectedView {
            case .glucose: return state.selectedGlucoseChartType.displayName
            case .insulin: return state.selectedInsulinChartType.displayName
            case .looping: return state.selectedLoopingChartType.displayName
            case .meals: return state.selectedMealChartType.displayName
            }
        }

        // MARK: - Range picker

        /// Chooses which days the `.today` interval reports on. Shown only while that interval
        /// is selected, since it means nothing for the rolling windows.
        ///
        /// Chevrons for the common move — the window either side of this one — and a tap on
        /// the dates to pick both ends. Both are bounded: there is no data past the stats
        /// screen's own three-month horizon, and none in the future.
        @ViewBuilder private var controlRow: some View {
            HStack(spacing: 0) {
                if isDayPickerVisible {
                    dayPicker
                } else {
                    Spacer()
                }

                chartTypeMenu
                    .frame(height: 28)
                    .padding(.leading, 8)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
            .padding(.top, -4)
        }

        @ViewBuilder private var dayPicker: some View {
            Group {
                Button {
                    shiftSelectedDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline)
                        .frame(width: 44, height: 28)
                        .contentShape(Rectangle())
                }
                .disabled(!canShiftSelectedDay(by: -1))
                .accessibilityLabel(Text("Previous period"))

                Spacer()

                // Gestures rather than a Button: a Button swallows the press, so a long press
                // layered on one either never fires or fires and then opens the sheet anyway
                // on release. Long press is the shortcut back from a window deep in the past;
                // the picker sheet has a "Today" button for the same jump.
                Text(selectedDayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .onLongPressGesture { jumpToToday() }
                    .onTapGesture { showDayPickerSheet = true }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text("Select days, \(selectedDayLabel)"))
                    .accessibilityAction { showDayPickerSheet = true }
                    .accessibilityAction(named: Text("Today")) { jumpToToday() }

                Spacer()

                Button {
                    shiftSelectedDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .frame(width: 44, height: 28)
                        .contentShape(Rectangle())
                }
                .disabled(!canShiftSelectedDay(by: 1))
                .accessibilityLabel(Text("Next period"))
            }
        }

        /// The range picker only means something for the calendar-day interval, and only the
        /// glucose and looping tabs offer it.
        private var isDayPickerVisible: Bool {
            switch selectedView {
            case .glucose: return state.selectedIntervalForGlucoseStats == .today
            case .looping: return state.selectedIntervalForLoopStats == .today
            case .insulin,
                 .meals: return false
            }
        }

        /// "Today" and "Yesterday" rather than their dates: on the two days people look at most,
        /// the name answers "which day is this?" faster than a date does. A range spanning more
        /// than one day names both its ends instead.
        private var selectedDayLabel: String {
            let calendar = Calendar.current
            let range = state.selectedStatsRange
            guard calendar.isDate(range.lowerBound, inSameDayAs: range.upperBound) else {
                return "\(shortDate(range.lowerBound)) – \(shortDate(range.upperBound))"
            }
            if calendar.isDateInToday(range.lowerBound) {
                return String(localized: "Today", comment: "Stats day picker: the current day")
            }
            if calendar.isDateInYesterday(range.lowerBound) {
                return String(localized: "Yesterday", comment: "Stats day picker: the previous day")
            }
            return range.lowerBound.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }

        private func shortDate(_ date: Date) -> String {
            date.formatted(.dateTime.day().month(.abbreviated))
        }

        /// The chevrons move the whole window by its own length, so a week-long range steps a
        /// week at a time rather than crawling a day per tap.
        private func shiftedRange(by steps: Int) -> ClosedRange<Date>? {
            let calendar = Calendar.current
            let days = steps * state.selectedStatsRangeDayCount
            guard
                let lower = calendar.date(byAdding: .day, value: days, to: state.selectedStatsRange.lowerBound),
                let upper = calendar.date(byAdding: .day, value: days, to: state.selectedStatsRange.upperBound)
            else { return nil }
            return lower ... upper
        }

        private func canShiftSelectedDay(by steps: Int) -> Bool {
            guard let shifted = shiftedRange(by: steps) else { return false }
            let calendar = Calendar.current
            return shifted.lowerBound >= calendar.startOfDay(for: state.earliestSelectableStatsDay)
                && shifted.upperBound <= calendar.startOfDay(for: Date())
        }

        private func jumpToToday() {
            let today = Calendar.current.startOfDay(for: Date())
            guard state.selectedStatsRange != today ... today else { return }
            state.selectedStatsRange = today ... today
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        private func shiftSelectedDay(by steps: Int) {
            guard canShiftSelectedDay(by: steps), let shifted = shiftedRange(by: steps) else { return }
            state.selectedStatsRange = shifted
        }

        /// Picks the window directly, for a stretch further off than a chevron or two. Two
        /// bounded pickers rather than one calendar: SwiftUI has no range date picker, and each
        /// end only ever needs to be a day.
        ///
        /// Both are clamped to the span the stats screen holds data for, and to each other, so
        /// the range can never invert or land where there is nothing to show.
        @ViewBuilder private var dayPickerSheet: some View {
            let earliest = Calendar.current.startOfDay(for: state.earliestSelectableStatsDay)
            let today = Calendar.current.startOfDay(for: Date())

            NavigationStack {
                Form {
                    Section {
                        DatePicker(
                            "From",
                            selection: Binding(
                                get: { state.selectedStatsRange.lowerBound },
                                set: { newValue in
                                    let start = Calendar.current.startOfDay(for: newValue)
                                    // Dragging the start past the end takes the end with it
                                    // rather than refusing the gesture.
                                    let end = max(start, state.selectedStatsRange.upperBound)
                                    state.selectedStatsRange = start ... end
                                }
                            ),
                            in: earliest ... today,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "To",
                            selection: Binding(
                                get: { state.selectedStatsRange.upperBound },
                                set: { newValue in
                                    let end = Calendar.current.startOfDay(for: newValue)
                                    let start = min(end, state.selectedStatsRange.lowerBound)
                                    state.selectedStatsRange = start ... end
                                }
                            ),
                            in: earliest ... today,
                            displayedComponents: .date
                        )
                    } footer: {
                        Text(rangeSummary)
                    }.listRowBackground(Color.chart)
                }
                .scrollContentBackground(.hidden)
                .background(appState.trioBackgroundColor(for: colorScheme))
                .navigationTitle("Select Days")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Today") {
                            state.selectedStatsRange = today ... today
                            showDayPickerSheet = false
                        }
                        .disabled(state.selectedStatsRange == today ... today)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDayPickerSheet = false }
                    }
                }
            }
            // One height, no drag to full screen: two rows and a footer, so the extra detent
            // only ever added blank space under them.
            .presentationDetents([.medium])
        }

        /// The span in whole days, so the picked window is legible before the sheet closes.
        private var rangeSummary: String {
            String(
                format: String(
                    localized: "%d days",
                    comment: "Stats range picker footer: how many whole days the range covers"
                ),
                state.selectedStatsRangeDayCount
            )
        }

        // MARK: - Stats View

        @ViewBuilder var glucoseView: some View {
            Picker("Duration", selection: $state.selectedIntervalForGlucoseStats) {
                ForEach(intervalOptions, id: \.self) { timeInterval in
                    Text(timeInterval.displayName)
                }
            }
            .pickerStyle(.segmented)

            controlRow

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
                    VStack(alignment: .leading) {
                        Text(hintText)
                        // Only while the day picker is on screen — it is the
                        // thing the gesture acts on.
                        if isDayPickerVisible {
                            Text("Tap and hold the selected date to return to today.")
                        }
                    }
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
                            case .today:
                                // A picked range draws at the granularity closest to its own
                                // length rather than being forced to a week.
                                return state.selectedStatsRangeInterval
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
                            // Only a range that is exactly today: the chart uses this to blank
                            // out hours that have not happened yet. On any past day, and on any
                            // multi-day range, every hour of the window already happened.
                            isToday: state.selectedIntervalForGlucoseStats == .today
                                && state.selectedStatsRangeDayCount == 1
                                && Calendar.current.isDateInToday(state.selectedStatsRange.lowerBound)
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
            Picker("Duration", selection: $state.selectedIntervalForInsulinStats) {
                ForEach(StateModel.StatsTimeInterval.allCases) { timeInterval in
                    Text(timeInterval.displayName).tag(timeInterval)
                }
            }
            .pickerStyle(.segmented)

            controlRow

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
            Picker("Duration", selection: $state.selectedIntervalForLoopStats) {
                ForEach(StateModel.StatsTimeIntervalWithToday.allCases, id: \.self) { interval in
                    Text(interval.displayName)
                }
            }
            .pickerStyle(.segmented)

            controlRow

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
            Picker("Duration", selection: $state.selectedIntervalForMealStats) {
                ForEach(StateModel.StatsTimeInterval.allCases, id: \.self) { timeInterval in
                    Text(timeInterval.displayName)
                }
            }
            .pickerStyle(.segmented)

            controlRow

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

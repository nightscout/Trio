import Charts
import SwiftUI

/// A view that displays a bar chart for Total Daily Dose (TDD) statistics.
///
/// This view presents insulin usage over time, with the ability to adjust the time interval
/// and scroll through historical data.
struct TotalDailyDoseChart: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    /// The list of TDD statistics data.
    let tddStats: [TDDStats]
    /// The state model containing cached statistics data.
    let state: Stat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The calculated average TDD for the visible range.
    @State private var currentAverage: Double = 0
    /// Timer to throttle updates when scrolling.
    @State private var updateTimer = Stat.UpdateTimer()
    /// Sum of hourly doses for `Day` view
    @State private var sumOfHourlyDoses: Double = 0

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedDuration)
    }

    /// Retrieves the TDD statistic for a given date.
    /// - Parameter date: The date for which to retrieve TDD data.
    /// - Returns: The `TDDStats` object if available, otherwise `nil`.
    private func getTDDForDate(_ date: Date) -> TDDStats? {
        tddStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedDuration)
        }
    }

    /// Updates the average TDD value based on the visible date range.
    private func updateAverages() {
        currentAverage = state.getCachedTDDAverages(for: visibleDateRange)
    }

    /// Updates the total of hourly doses for `Day` view
    private func updateTotalDoses() {
        sumOfHourlyDoses = tddStats.filter({ $0.date >= visibleDateRange.start && $0.date <= visibleDateRange.end })
            .reduce(0, { result, stat in
                result + stat.amount
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text("Total Daily Dose (U)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chartsView
            }
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedDuration)
            updateAverages()
            updateTotalDoses()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
                if selectedDuration == .Day {
                    updateTotalDoses()
                }
            }
        }
        .onChange(of: selectedDuration) {
            Task {
                scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedDuration)
                updateAverages()
                if selectedDuration == .Day {
                    updateTotalDoses()
                }
            }
        }
    }

    /// A view displaying the statistics summary including average TDD.
    private var statsView: some View {
        HStack {
            if selectedDuration == .Day {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Total:")
                            .font(.headline)
                        Text(sumOfHourlyDoses.formatted(.number.precision(.fractionLength(1))))
                            .font(.headline)
                        Text("U")
                            .font(.headline)
                    }
                    GridRow {
                        Text("Average:")
                            .font(.headline)
                        Text(currentAverage.formatted(.number.precision(.fractionLength(1))))
                            .font(.headline)
                        Text("U")
                            .font(.headline)
                    }
                }
                .font(.headline)
            } else {
                Text("Average:")
                    .font(.headline)
                Text(currentAverage.formatted(.number.precision(.fractionLength(1))))
                    .font(.headline)
                Text("U")
                    .font(.headline)
            }
            Spacer()

            Text(
                StatChartUtils
                    .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedDuration)
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// A view displaying the bar chart for TDD statistics.
    private var chartsView: some View {
        Chart {
            ForEach(tddStats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(Color.insulin)
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedDuration) ? 1 : 0.3
                    } ?? 1
                )
            }

            // Selection popover outside of the ForEach loop!
            if let selectedDate,
               let selectedTDD = getTDDForDate(selectedDate)
            {
                RuleMark(
                    x: .value("Selected Date", selectedDate)
                )
                .foregroundStyle(.secondary.opacity(0.5))
                .annotation(
                    position: .top,
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    TDDSelectionPopover(date: selectedDate, tdd: selectedTDD, selectedDuration: selectedDuration)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let amount = value.as(Double.self) {
                    AxisValueLabel {
                        Text(amount.formatted(.number.precision(.fractionLength(0))))
                            .font(.footnote)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: selectedDuration == .Day ? .hour : .day)) { value in
                if let date = value.as(Date.self) {
                    let day = Calendar.current.component(.day, from: date)
                    let hour = Calendar.current.component(.hour, from: date)

                    switch selectedDuration {
                    case .Day:
                        if hour % 6 == 0 { // Show only every 6 hours
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .Month:
                        if day % 3 == 0 { // Only show every 3rd day
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .Total:
                        // Only show every other month
                        if day == 1 && Calendar.current.component(.month, from: date) % 2 == 1 {
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedDuration), centered: true)
                            .font(.footnote)
                        AxisGridLine()
                    }
                }
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: selectedDuration == .Day ?
                    DateComponents(minute: 0) :
                    DateComponents(hour: 0),
                majorAlignment: .matching(StatChartUtils.alignmentComponents(for: selectedDuration))
            )
        )
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedDuration))
        .frame(height: 250)
    }
}

/// A popover view displaying TDD (Total Daily Dose) for a given time period.
/// Shows the insulin amount in units (U) for an hourly or daily interval, depending on `selectedDuration`.
///
/// - Parameters:
///   - date: The reference date for determining the displayed time range.
///   - tdd: The TDDStats containing insulin usage data.
///   - selectedDuration: The selected time interval (hourly or daily).
private struct TDDSelectionPopover: View {
    let date: Date
    let tdd: TDDStats
    let selectedDuration: Stat.StateModel.StatsTimeInterval

    private var timeText: String {
        if selectedDuration == .Day {
            let hour = Calendar.current.component(.hour, from: date)
            return "\(hour):00-\(hour + 1):00"
        } else {
            return date.formatted(.dateTime.month().day())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeText)
                .font(.subheadline)
                .fontWeight(.bold)

            Text(tdd.amount.formatted(.number.precision(.fractionLength(1))) + " U")
                .font(.title3.bold())
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.insulin)
        }
    }
}

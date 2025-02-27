import Charts
import SwiftUI

/// A view that displays a bar chart for bolus insulin statistics.
///
/// This view presents different types of bolus insulin (manual, SMB, and external) over time,
/// allowing users to adjust the time interval and scroll through historical data.
struct BolusStatsView: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    /// The list of bolus statistics data.
    let bolusStats: [BolusStats]
    /// The state model containing cached statistics data.
    let state: Stat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The calculated bolus insulin averages for the visible range.
    @State private var currentAverages: (manual: Double, smb: Double, external: Double) = (0, 0, 0)
    /// Timer to throttle updates when scrolling.
    @State private var updateTimer = Stat.UpdateTimer()

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatsHelper.visibleDateRange(from: scrollPosition, for: selectedDuration)
    }

    /// Retrieves the bolus statistic for a given date.
    /// - Parameter date: The date for which to retrieve bolus data.
    /// - Returns: The `BolusStats` object if available, otherwise `nil`.
    private func getBolusForDate(_ date: Date) -> BolusStats? {
        bolusStats.first { stat in
            StatsHelper.isSameTimeUnit(stat.date, date, for: selectedDuration)
        }
    }

    /// Updates the bolus insulin averages based on the visible date range.
    private func updateAverages() {
        currentAverages = state.getCachedBolusAverages(for: visibleDateRange)
    }

    /// A view displaying the statistics summary including bolus insulin averages.
    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                GridRow {
                    Text("Manual:")
                    Text(currentAverages.manual.formatted(.number.precision(.fractionLength(1))))
                    Text("U")
                }
                GridRow {
                    Text("SMB:")
                    Text(currentAverages.smb.formatted(.number.precision(.fractionLength(1))))
                    Text("U")
                }
                GridRow {
                    Text("External:")
                    Text(currentAverages.external.formatted(.number.precision(.fractionLength(1))))
                    Text("U")
                }
            }
            .font(.headline)

            Spacer()

            Text(
                StatsHelper
                    .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedDuration)
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView
            chartsView
        }
        .onAppear {
            scrollPosition = StatsHelper.getInitialScrollPosition(for: selectedDuration)
            updateAverages()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
            }
        }
        .onChange(of: selectedDuration) {
            Task {
                scrollPosition = StatsHelper.getInitialScrollPosition(for: selectedDuration)
                updateAverages()
            }
        }
    }

    /// A view displaying the bar chart for bolus insulin statistics.
    private var chartsView: some View {
        Chart {
            ForEach(bolusStats) { stat in
                // Total Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.manualBolus)
                )
                .foregroundStyle(by: .value("Type", "Manual"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatsHelper.isSameTimeUnit(stat.date, date, for: selectedDuration) ? 1 : 0.3
                    } ?? 1
                )

                // Carb Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.smb)
                )
                .foregroundStyle(by: .value("Type", "SMB"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatsHelper.isSameTimeUnit(stat.date, date, for: selectedDuration) ? 1 : 0.3
                    } ?? 1
                )
                // Correction Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.external)
                )
                .foregroundStyle(by: .value("Type", "External"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatsHelper.isSameTimeUnit(stat.date, date, for: selectedDuration) ? 1 : 0.3
                    } ?? 1
                )
            }

            // Selection popover outside of the ForEach loop!
            if let selectedDate, let selectedBolus = getBolusForDate(selectedDate)
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
                    BolusSelectionPopover(date: selectedDate, bolus: selectedBolus, selectedDuration: selectedDuration)
                }
            }
        }
        .chartForegroundStyleScale([
            "SMB": Color.blue,
            "Manual": Color.teal,
            "External": Color.purple
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let amount = value.as(Double.self) {
                    AxisValueLabel {
                        Text(amount.formatted(.number.precision(.fractionLength(0))) + " U")
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
                            AxisValueLabel(format: StatsHelper.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .Month:
                        if day % 5 == 0 { // Only show every 5th day
                            AxisValueLabel(format: StatsHelper.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .Total:
                        // Only show January, April, July, October
                        if day == 1 && Calendar.current.component(.month, from: date) % 3 == 1 {
                            AxisValueLabel(format: StatsHelper.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel(format: StatsHelper.dateFormat(for: selectedDuration), centered: true)
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
                    DateComponents(minute: 0) : // Align to next hour for Day view
                    DateComponents(hour: 0), // Align to start of day for other views
                majorAlignment: .matching(
                    StatsHelper.alignmentComponents(for: selectedDuration)
                )
            )
        )
        .chartXVisibleDomain(length: StatsHelper.visibleDomainLength(for: selectedDuration))
        .frame(height: 250)
    }
}

private struct BolusSelectionPopover: View {
    let date: Date
    let bolus: BolusStats
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
                .font(.footnote)
                .fontWeight(.bold)

            Grid(alignment: .leading) {
                GridRow {
                    Text("Manual:")
                    Text(bolus.manualBolus.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("U")
                }
                GridRow {
                    Text("SMB:")
                    Text(bolus.smb.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("U")
                }
                GridRow {
                    Text("External:")
                    Text(bolus.external.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("U")
                }
            }
            .font(.headline.bold())
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.insulin)
        )
    }
}

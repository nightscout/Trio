import Charts
import SwiftUI

/// A view that displays a bar chart for bolus insulin statistics.
///
/// This view presents different types of bolus insulin (manual, SMB, and external) over time,
/// allowing users to adjust the time interval and scroll through historical data.
struct BolusStatsView: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
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
    /// The calculated total bolus insulin for the visible range.
    @State private var currentTotal: Double = 0
    /// Timer to throttle updates when scrolling.
    @State private var updateTimer = Stat.UpdateTimer()
    /// The actual chart plot's width in pixel
    @State private var chartWidth: CGFloat = 0

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// Retrieves the bolus statistic for a given date.
    /// - Parameter date: The date for which to retrieve bolus data.
    /// - Returns: The `BolusStats` object if available, otherwise `nil`.
    private func getBolusForDate(_ date: Date) -> BolusStats? {
        bolusStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    /// Updates the bolus insulin averages based on the visible date range.
    private func updateCalculatedValues() {
        currentAverages = state.getCachedBolusAverages(for: visibleDateRange)
        currentTotal = state.getCachedBolusTotals(for: visibleDateRange)
    }

    /// A view displaying the statistics summary including bolus insulin averages.
    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                GridRow {
                    if selectedInterval != .day {
                        Text("ø") + Text("\u{00A0}") + Text("Manual:")
                    } else {
                        Text("Manual:")
                    }
                    Text(currentAverages.manual.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                GridRow {
                    if selectedInterval != .day {
                        Text("ø") + Text("\u{00A0}") + Text("SMB:")
                    } else {
                        Text("SMB:")
                    }
                    Text(currentAverages.smb.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                GridRow {
                    if selectedInterval != .day {
                        Text("ø") + Text("\u{00A0}") + Text("External:")
                    } else {
                        Text("External:")
                    }
                    Text(currentAverages.external.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                Divider()
                GridRow {
                    Text("Total:")
                    Text(
                        currentTotal.formatted(.number.precision(.fractionLength(1)))
                    )
                        + Text("\u{00A0}") + Text("U")
                }
            }
            .font(.headline)

            Spacer()

            Text(
                StatChartUtils
                    .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedInterval)
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text("Bolus Insulin (U)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chartsView
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { chartWidth = geo.size.width }
                                .onChange(of: geo.size.width) { _, newValue in chartWidth = newValue }
                        }
                    )
            }
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
            updateCalculatedValues()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateCalculatedValues()
            }
        }
        .onChange(of: selectedInterval) {
            Task {
                scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
                updateCalculatedValues()
            }
        }
    }

    /// A view displaying the bar chart for bolus insulin statistics.
    private var chartsView: some View {
        Chart {
            ForEach(bolusStats) { stat in
                // Total Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.manualBolus)
                )
                .foregroundStyle(by: .value("Type", "Manual"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )

                // Carb Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.smb)
                )
                .foregroundStyle(by: .value("Type", "SMB"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
                // Correction Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.external)
                )
                .foregroundStyle(by: .value("Type", "External"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
            }

            // Dummy PointMark to force SwiftCharts to render a visible domain of 00:00-23:59
            // i.e. single day from midnight to midnight
            if selectedInterval == .day {
                let calendar = Calendar.current
                let midnight = calendar.startOfDay(for: Date())
                let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight)!

                PointMark(
                    x: .value("Time", nextMidnight),
                    y: .value("Dummy", 0)
                )
                .opacity(0) // ensures dummy ChartContent is hidden
            }

            // Selection popover outside of the ForEach loop!
            if let selectedDate, let selectedBolus = getBolusForDate(selectedDate)
            {
                RuleMark(
                    x: .value("Selected Date", selectedDate)
                )
                .foregroundStyle(Color.insulin.opacity(0.5))
                .annotation(
                    position: .overlay,
                    alignment: .top,
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) { _ in
                    BolusSelectionPopover(
                        selectedDate: selectedDate,
                        bolus: selectedBolus,
                        selectedInterval: selectedInterval,
                        domain: visibleDateRange,
                        chartWidth: chartWidth
                    )
                }
            }
        }
        .chartForegroundStyleScale([
            "SMB": Color.blue,
            "Manual": Color.teal,
            "External": Color.purple
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
            let legendItems: [(String, Color)] = [
                (String(localized: "SMB"), Color.blue),
                (String(localized: "Manual"), Color.teal),
                (String(localized: "External"), Color.purple)
            ]

            let columns = [GridItem(.adaptive(minimum: 65), spacing: 4)]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(legendItems, id: \.0) { item in
                    StatChartUtils.legendItem(label: item.0, color: item.1)
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
            AxisMarks(preset: .aligned, values: .stride(by: selectedInterval == .day ? .hour : .day)) { value in
                if let date = value.as(Date.self) {
                    let day = Calendar.current.component(.day, from: date)
                    let hour = Calendar.current.component(.hour, from: date)

                    switch selectedInterval {
                    case .day:
                        if hour % 6 == 0 { // Show only every 6 hours
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .month:
                        if day % 3 == 0 { // Only show every 3rd day
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .total:
                        // Only show every other month
                        if day == 1 && Calendar.current.component(.month, from: date) % 2 == 1 {
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                            .font(.footnote)
                        AxisGridLine()
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching:
                selectedInterval == .day ?
                    DateComponents(minute: 0) : // Align to next hour for Day view
                    DateComponents(hour: 0), // Align to start of day for other views
                majorAlignment: .matching(
                    StatChartUtils.alignmentComponents(for: selectedInterval)
                )
            )
        )
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedInterval))
        .frame(height: 280)
    }
}

private struct BolusSelectionPopover: View {
    let selectedDate: Date
    let bolus: BolusStats
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let domain: (start: Date, end: Date)
    let chartWidth: CGFloat

    @State private var popoverSize: CGSize = .zero

    @Environment(\.colorScheme) var colorScheme

    private var timeText: String {
        if selectedInterval == .day {
            let hour = Calendar.current.component(.hour, from: selectedDate)
            return selectedDate.formatted(.dateTime.month().day().weekday()) + "\n" + "\(hour):00-\(hour + 1):00"
        } else {
            return selectedDate.formatted(.dateTime.month().day().weekday())
        }
    }

    private func xOffset() -> CGFloat {
        let domainDuration = domain.end.timeIntervalSince(domain.start)
        guard domainDuration > 0, chartWidth > 0 else { return 0 }

        let popoverWidth = popoverSize.width

        // Convert dates to pixel'd x-condition
        let dateFraction = selectedDate.timeIntervalSince(domain.start) / domainDuration
        let x_selected = dateFraction * chartWidth

        // TODO: this is semi hacky, can this be improved?
        let x_left = x_selected - (popoverWidth / 2) // Left edge of popover
        let x_right = x_selected + (popoverWidth / 2) // Right edge of popover

        var offset: CGFloat = 0 // Default = no shift

        // Push popover to right if its left edge is (nearing) out-of-bounds
        if x_left < 0 {
            offset = abs(x_left) // push to right
        }

        // Push popover to left if its right edge is (nearing) out-of-bounds)
        if x_right > chartWidth {
            offset = -(x_right - chartWidth) // push to left
        }

        return offset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeText)
                .font(.subheadline)
                .bold()
                .foregroundStyle(Color.secondary)

            Grid(alignment: .leading) {
                Divider()
                GridRow {
                    Text("Manual:")
                    Text(bolus.manualBolus.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing).bold()
                    Text("U").foregroundStyle(Color.secondary)
                }
                GridRow {
                    Text("SMB:")
                    Text(bolus.smb.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing).bold()
                    Text("U").foregroundStyle(Color.secondary)
                }
                GridRow {
                    Text("External:")
                    Text(bolus.external.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing).bold()
                    Text("U").foregroundStyle(Color.secondary)
                }
                Divider()
                GridRow {
                    Text("Total:")
                    Text(
                        (bolus.manualBolus + bolus.smb + bolus.external).formatted(.number.precision(.fractionLength(1)))
                    ).bold()
                    Text("U").foregroundStyle(Color.secondary)
                }
            }
            .font(.headline)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.bgDarkBlue.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue, lineWidth: 2)
                )
        }
        .frame(minWidth: 180, maxWidth: .infinity) // Ensures proper width
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { popoverSize = geo.size }
                    .onChange(of: geo.size) { _, newValue in popoverSize = newValue }
            }
        )
        // Apply calculated xOffset to keep within bounds
        .offset(x: xOffset(), y: 0)
    }
}

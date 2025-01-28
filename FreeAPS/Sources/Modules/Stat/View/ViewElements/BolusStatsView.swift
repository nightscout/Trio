import Charts
import SwiftUI

struct BolusStatsView: View {
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    let bolusStats: [BolusStats]
    let calculateAverages: @Sendable(Date, Date) async -> (manual: Double, smb: Double, external: Double)

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?
    @State private var currentAverages: (manual: Double, smb: Double, external: Double) = (0, 0, 0)
    @State private var updateTimer = Stat.UpdateTimer()

    private var visibleDomainLength: TimeInterval {
        switch selectedDuration {
        case .Day: return 24 * 3600 // 1 day
        case .Week: return 7 * 24 * 3600 // 1 week
        case .Month: return 30 * 24 * 3600 // 1 month
        case .Total: return 90 * 24 * 3600 // 3 months
        }
    }

    private var visibleDateRange: (start: Date, end: Date) {
        let halfDomain = visibleDomainLength / 2
        let start = scrollPosition.addingTimeInterval(-halfDomain)
        let end = scrollPosition.addingTimeInterval(halfDomain)
        return (start, end)
    }

    private var dateFormat: Date.FormatStyle {
        switch selectedDuration {
        case .Day:
            return .dateTime.weekday(.abbreviated)
        case .Week:
            return .dateTime.weekday(.abbreviated)
        case .Month:
            return .dateTime.day()
        case .Total:
            return .dateTime.month(.abbreviated)
        }
    }

    private var alignmentComponents: DateComponents {
        switch selectedDuration {
        case .Day:
            return DateComponents(hour: 0) // Align to start of day
        case .Week:
            return DateComponents(weekday: 2) // 2 = Monday in Calendar
        case .Month,
             .Total:
            return DateComponents(day: 1) // Align to first day of month
        }
    }

    private func getBolusForDate(_ date: Date) -> BolusStats? {
        bolusStats.first { stat in
            Calendar.current.isDate(stat.date, inSameDayAs: date)
        }
    }

    private func updateAverages() {
        Task.detached(priority: .userInitiated) {
            let dateRange = await MainActor.run { visibleDateRange }
            let averages = await calculateAverages(dateRange.start, dateRange.end)

            await MainActor.run {
                currentAverages = averages
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView

            Chart {
                ForEach(bolusStats) { stat in
                    // External Bolus (Bottom)
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.external)
                    )
                    .foregroundStyle(by: .value("Type", "External"))

                    // SMB (Middle)
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.smb)
                    )
                    .foregroundStyle(by: .value("Type", "SMB"))

                    // Manual Bolus (Top)
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.manualBolus)
                    )
                    .foregroundStyle(by: .value("Type", "Manual"))
                }

                if let selectedDate,
                   let selectedBolus = getBolusForDate(selectedDate)
                {
                    RuleMark(
                        x: .value("Selected Date", selectedDate)
                    )
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit, y: .disabled)
                    ) {
                        BolusSelectionPopover(date: selectedDate, bolus: selectedBolus)
                    }
                }
            }
            .chartForegroundStyleScale([
                "Manual": Color.teal,
                "SMB": Color.blue,
                "External": Color.purple
            ])
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let amount = value.as(Double.self) {
                        AxisValueLabel {
                            Text(amount.formatted(.number.precision(.fractionLength(1))) + " U")
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        let day = Calendar.current.component(.day, from: date)

                        switch selectedDuration {
                        case .Month:
                            if day % 5 == 0 { // Only show every 5th day
                                AxisValueLabel(format: dateFormat)
                                AxisGridLine()
                            }
                        case .Total:
                            // Only show January, April, July, October
                            if day == 1 && Calendar.current.component(.month, from: date) % 3 == 1 {
                                AxisValueLabel(format: dateFormat)
                                AxisGridLine()
                            }
                        default:
                            AxisValueLabel(format: dateFormat)
                            AxisGridLine()
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $scrollPosition)
            .chartScrollTargetBehavior(
                .valueAligned(
                    matching: DateComponents(hour: 0), // Align to start of day
                    majorAlignment: .matching(alignmentComponents)
                )
            )
            .chartXVisibleDomain(length: visibleDomainLength)
            .frame(height: 200)
        }

        .onAppear {
            updateAverages()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
            }
        }
        .onChange(of: selectedDuration) {
            updateAverages()
            scrollPosition = Date()
        }
    }

    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                GridRow {
                    Text("Manual:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.manual.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("U")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("SMB:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.smb.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("U")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("External:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.external.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("U")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(
                "\(visibleDateRange.start.formatted(.dateTime.month().day())) - \(visibleDateRange.end.formatted(.dateTime.month().day()))"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

private struct BolusSelectionPopover: View {
    let date: Date
    let bolus: BolusStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.month().day()))
                .font(.caption)
                .foregroundStyle(.secondary)

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
            .font(.caption)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(radius: 2)
        )
    }
}

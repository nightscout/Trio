import Charts
import SwiftUI

struct TDDChartView: View {
    private enum Constants {
        static let dayOptions = [3, 5, 7, 10, 14, 21, 28]
        static let chartHeight: CGFloat = 200
        static let spacing: CGFloat = 8
        static let cornerRadius: CGFloat = 10
        static let summaryBackgroundOpacity = 0.1
    }

    let state: Stat.StateModel
    @Binding var selectedDays: Int
    @Binding var selectedEndDate: Date
    @Binding var dailyTotalDoses: [TDD]
    var averageTDD: Decimal
    var ytdTDD: Decimal

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: Constants.spacing) {
            dateSelectionView
            summaryCardView
            chartCard
        }
    }

    // MARK: - Views

    private var dateSelectionView: some View {
        HStack {
            Text("Time Frame")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            CustomDatePicker(selection: $selectedEndDate)
                .frame(height: 30)

            Picker("Days", selection: $selectedDays) {
                ForEach(Constants.dayOptions, id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var summaryCardView: some View {
        VStack(spacing: Constants.spacing) {
            tddRow(
                title: "Today",
                value: state.currentTDD
            )
            Divider()
            tddRow(
                title: "Yesterday",
                value: ytdTDD
            )
            Divider()
            tddRow(
                title: "Average \(selectedDays) days",
                value: averageTDD
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.secondary.opacity(Constants.summaryBackgroundOpacity))
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Constants.spacing) {
            Text("Total Daily Doses")
                .font(.headline)

            Chart {
                ForEach(chartData, id: \.date) { entry in
                    BarMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Insulin", entry.dose)
                    )
                    .foregroundStyle(Color.insulin.gradient)
                    .annotation(position: .top) {
                        if entry.dose > 0 {
                            Text(formatDose(entry.dose))
                                .font(.caption2)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                if let average = calculateAverage() {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(.primary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .automatic) {
                            Text("\(formatDose(average)) U")
                                .font(.caption)
                                .foregroundStyle(Color.insulin)
                        }
                }
            }
            .chartXAxis {
                tddChartXAxisMarks
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .chartYAxisLabel(alignment: .trailing) {
                Text("Units (U)")
                    .foregroundColor(.primary)
            }
            .chartYScale(domain: 0 ... calculateYAxisMaximum())
        }
        .frame(height: 200)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.secondary.opacity(Constants.summaryBackgroundOpacity))
        )
    }

    // MARK: - Helper Views

    private var tddChartXAxisMarks: some AxisContent {
        AxisMarks(values: .stride(by: .day)) { value in
            if let date = value.as(Date.self),
               xAxisLabelValues().contains(where: { $0.date == date })
            {
                AxisValueLabel(xAxisLabelValues().first { $0.date == date }?.label ?? "")
            }
            AxisGridLine()
        }
    }

    private func tddRow(title: String, value: Decimal) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatDose(value))
                .foregroundColor(.primary)
            Text("U")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    // MARK: - Data Processing

    private var chartData: [(date: Date, dose: Decimal)] {
        completeData(forDays: selectedDays)
    }

    private func calculateAverage() -> Decimal? {
        let nonZeroDoses = chartData.map(\.dose).filter { $0 > 0 }
        guard !nonZeroDoses.isEmpty else { return nil }
        return nonZeroDoses.reduce(0, +) / Decimal(nonZeroDoses.count)
    }

    private func calculateYAxisMaximum() -> Double {
        let maxDose = chartData.map(\.dose).max() ?? 0
        let average = calculateAverage() ?? 0
        return (max(maxDose, average) * 1.2).doubleValue // Add 20% padding
    }

    private func formatDose(_ value: Decimal) -> String {
        Formatter.decimalFormatterWithOneFractionDigit.string(from: value as NSNumber) ?? "0"
    }

    private func completeData(forDays days: Int) -> [(date: Date, dose: Decimal)] {
        var completeData: [(date: Date, dose: Decimal)] = []
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: selectedEndDate)

        for _ in 0 ..< days {
            if let existingEntry = dailyTotalDoses.first(where: { entry in
                guard let timestamp = entry.timestamp else { return false }
                return calendar.isDate(timestamp, inSameDayAs: currentDate)
            }) {
                completeData.append((date: currentDate, dose: existingEntry.totalDailyDose ?? 0))
            } else {
                completeData.append((date: currentDate, dose: 0))
            }
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
        }
        return completeData.reversed()
    }

    private func xAxisLabelValues() -> [(date: Date, label: String)] {
        let data = chartData
        let stride = selectedDays > 13 ? max(1, selectedDays / 7) : 1

        return data.enumerated().compactMap { index, entry in
            if index % stride == 0 || index == data.count - 1 {
                return (date: entry.date, label: Formatter.dayFormatter.string(from: entry.date))
            }
            return nil
        }
    }
}

private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

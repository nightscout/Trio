import Charts
import SwiftUI

struct BolusStatsView: View {
    let bolusStats: [BolusStats]
    @Binding var selectedDays: Int
    @Binding var selectedEndDate: Date

    private var hasData: Bool {
        bolusStats.contains { $0.manualBolus > 0 || $0.smb > 0 || $0.external > 0 }
    }

    var body: some View {
        if bolusStats.isEmpty || !hasData {
            ContentUnavailableView(
                "No Bolus Data",
                systemImage: "cross.vial",
                description: Text("Bolus statistics will appear here once data is available.")
            )
        } else {
            StatCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bolus Distribution")
                        .font(.headline)

                    Chart(bolusStats) { stat in
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
                    .chartForegroundStyleScale([
                        "Manual": Color.teal,
                        "SMB": Color.blue,
                        "External": Color.purple
                    ])
                    .chartLegend(position: .top, alignment: .leading, spacing: 12)
                    .frame(height: 200)
                    .chartXAxis {
                        bolusStatsChartXAxisMarks
                    }
                    .chartYAxis {
                        bolusStatsChartYAxisMarks
                    }
                }
            }
            .padding()
        }
    }

    private var bolusStatsChartXAxisMarks: some AxisContent {
        AxisMarks { value in
            if let date = value.as(Date.self) {
                AxisValueLabel {
                    if selectedDays < 8 {
                        Text(date, format: .dateTime.weekday(.abbreviated))
                    } else {
                        Text(date, format: .dateTime.day().month(.defaultDigits))
                    }
                }
                AxisGridLine()
            }
        }
    }

    private var bolusStatsChartYAxisMarks: some AxisContent {
        AxisMarks(position: .leading) { value in
            if let amount = value.as(Double.self) {
                AxisValueLabel {
                    Text(amount.formatted(.number.precision(.fractionLength(1))) + " U")
                }
                AxisGridLine()
            }
        }
    }
}

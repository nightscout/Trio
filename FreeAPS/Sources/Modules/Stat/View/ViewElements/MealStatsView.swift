import Charts
import SwiftUI

struct MealStatsView: View {
    let mealStats: [MealStats]
    let selectedDuration: Stat.StateModel.Duration

    var body: some View {
        StatCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Macronutrients")
                    .font(.headline)

                Chart(mealStats) { stat in
                    // Carbs Bar
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.carbs),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(Color.orange)
                    .position(by: .value("Nutrient", "Carbs"))

                    // Fat Bar
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.fat),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(Color.yellow)
                    .position(by: .value("Nutrient", "Fat"))

                    // Protein Bar
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.protein),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(Color.green)
                    .position(by: .value("Nutrient", "Protein"))
                }
                .chartForegroundStyleScale([
                    "Carbs": Color.orange,
                    "Fat": Color.yellow,
                    "Protein": Color.green
                ])
                .chartLegend(position: .top, alignment: .leading, spacing: 12)
                .frame(height: 200)
                .chartXAxis {
                    mealChartXAxisMarks
                }
                .chartYAxis {
                    mealChartYAxisMarks
                }
            }
        }
    }

    private var mealChartXAxisMarks: some AxisContent {
        AxisMarks { value in
            if let date = value.as(Date.self) {
                AxisValueLabel {
                    switch selectedDuration {
                    case .Day,
                         .Today,
                         .Week:
                        Text(date, format: .dateTime.weekday(.abbreviated))
                    case .Month,
                         .Total:
                        Text(date, format: .dateTime.day().month(.defaultDigits))
                    }
                }
                AxisGridLine()
            }
        }
    }

    private var mealChartYAxisMarks: some AxisContent {
        AxisMarks(position: .leading) { value in
            if let amount = value.as(Double.self) {
                AxisValueLabel {
                    Text("\(Int(amount))g")
                }
                AxisGridLine()
            }
        }
    }
}

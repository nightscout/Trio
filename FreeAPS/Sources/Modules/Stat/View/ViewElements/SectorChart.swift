import Charts
import CoreData
import SwiftDate
import SwiftUI

struct SectorChart: View {
    private enum Constants {
        static let chartHeight: CGFloat = 200
        static let spacing: CGFloat = 8
        static let labelSpacing: CGFloat = 4
    }

    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let hbA1cDisplayUnit: HbA1cDisplayUnit
    let timeInRangeChartStyle: TimeInRangeChartStyle
    let glucose: [GlucoseStored]

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 20) {
            Chart {
                ForEach(timeInRangeData, id: \.string) { data in
                    SectorMark(
                        angle: .value("Percentage", data.decimal),
                        innerRadius: .ratio(0.618), // Golden ratio
                        angularInset: 1.5
                    )
                    .foregroundStyle(data.color.gradient)
                }
            }
            .frame(height: Constants.chartHeight)

            // Legend
            VStack(spacing: Constants.spacing) {
                ForEach(timeInRangeData, id: \.string) { data in
                    HStack(spacing: Constants.spacing) {
                        Circle()
                            .fill(data.color)
                            .frame(width: 12, height: 12)

                        Text(data.string)
                            .font(.subheadline)

                        Spacer()

                        Text(formatPercentage(data.decimal))
                            .font(.subheadline)
                            .bold()
                    }
                }
            }
            .padding(.top, Constants.spacing)
        }
    }

    // MARK: - Data Processing

    private var timeInRangeData: [(decimal: Decimal, string: String, color: Color)] {
        let total = glucose.count
        guard total > 0 else { return [] }

        let hyperArray = glucose.filter { $0.glucose >= Int(highLimit) }
        let hyperReadings = hyperArray.count
        let hyperPercentage = Decimal(hyperReadings) / Decimal(total) * 100

        let hypoArray = glucose.filter { $0.glucose <= Int(lowLimit) }
        let hypoReadings = hypoArray.count
        let hypoPercentage = Decimal(hypoReadings) / Decimal(total) * 100

        let normalPercentage = 100 - (hypoPercentage + hyperPercentage)

        return [
            (normalPercentage, "In Range", .green),
            (hyperPercentage, "High", .yellow),
            (hypoPercentage, "Low", .red)
        ]
    }

    private func formatPercentage(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSDecimalNumber(decimal: value / 100)) ?? "0%"
    }
}

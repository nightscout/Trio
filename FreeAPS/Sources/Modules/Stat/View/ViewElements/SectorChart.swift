import Charts
import CoreData
import SwiftDate
import SwiftUI

struct SectorChart: View {
    private enum Constants {
        static let chartHeight: CGFloat = 160
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
        HStack(alignment: .center, spacing: 20) {
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
            .padding(.vertical)
            .frame(height: Constants.chartHeight)

            // Legend
            VStack(spacing: Constants.spacing) {
                ForEach(timeInRangeData, id: \.string) { data in
                    HStack(spacing: Constants.spacing) {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(data.color)
                            .font(.caption2)

                        Text(data.string)
                            .font(.footnote)

                        Spacer()

                        Text(formatPercentage(data.decimal))
                            .font(.footnote)
                            .bold()
                    }
                }
            }
        }
    }

    // MARK: - Data Processing

    private var timeInRangeData: [(decimal: Decimal, string: String, color: Color)] {
        let total = glucose.count
        guard total > 0 else { return [] }

        let hyperArray = glucose.filter { $0.glucose > Int(highLimit) && $0.glucose <= 250 }
        let hyperPercentage = Decimal(hyperArray.count) / Decimal(total) * 100

        let severeHyperArray = glucose.filter { $0.glucose > 250 }
        let severeHyperPercentage = Decimal(severeHyperArray.count) / Decimal(total) * 100

        let hypoArray = glucose.filter { $0.glucose < Int(lowLimit) && $0.glucose > 54 }
        let hypoPercentage = Decimal(hypoArray.count) / Decimal(total) * 100

        let severeHypoArray = glucose.filter { $0.glucose <= 54 }
        let severeHypoPercentage = Decimal(severeHypoArray.count) / Decimal(total) * 100

        let normalPercentage = 100 - (hypoPercentage + severeHypoPercentage + severeHyperPercentage + hyperPercentage)

        let timeInTighterRangeArray = glucose.filter { $0.glucose >= Int(lowLimit) && $0.glucose <= 140 }
        let timeInTighterRangePercentage = Decimal(timeInTighterRangeArray.count) / Decimal(total) * 100

        return [
            (severeHyperPercentage, "Very High", .orange),
            (hyperPercentage, "High", .orange.opacity(0.6)),
            (normalPercentage, "In Range", .green.opacity(0.6)),
            (timeInTighterRangePercentage, "Tight Range", .green),
            (hypoPercentage, "Low", .red.opacity(0.6)),
            (severeHypoPercentage, "Very Low", .red)
        ]
    }

    private func formatPercentage(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSDecimalNumber(decimal: value / 100)) ?? "0%"
    }
}

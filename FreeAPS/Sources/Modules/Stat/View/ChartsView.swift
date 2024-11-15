import Charts
import CoreData
import SwiftDate
import SwiftUI

struct ChartsView: View {
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let hbA1cDisplayUnit: HbA1cDisplayUnit
    let timeInRangeChartStyle: TimeInRangeChartStyle

    let glucose: [GlucoseStored]

    @State var headline: Color = .secondary

    private var conversionFactor: Decimal {
        units == .mmolL ? 0.0555 : 1
    }

    var body: some View {
        glucoseChart
        Rectangle().fill(.cyan.opacity(0.2)).frame(maxHeight: 3)
        if timeInRangeChartStyle == .horizontal {
            VStack {
                tirChart
                Rectangle().fill(.cyan.opacity(0.2)).frame(maxHeight: 3)
                groupedGlucoseStatsLaying
            }
        } else {
            HStack(spacing: 20) {
                standingTIRchart
                groupedGlucose
            }
        }
    }

    init(
        highLimit: Decimal,
        lowLimit: Decimal,
        units: GlucoseUnits,
        hbA1cDisplayUnit: HbA1cDisplayUnit,
        timeInRangeChartStyle: TimeInRangeChartStyle,
        glucose: [GlucoseStored]
    ) {
        self.highLimit = highLimit
        self.lowLimit = lowLimit
        self.units = units
        self.hbA1cDisplayUnit = hbA1cDisplayUnit
        self.timeInRangeChartStyle = timeInRangeChartStyle
        self.glucose = glucose
    }

    var glucoseChart: some View {
        let low = lowLimit * conversionFactor
        let high = highLimit * conversionFactor
        let count = glucose.count
        // The symbol size when fewer readings are larger
        let size: CGFloat = count < 20 ? 50 : count < 50 ? 35 : count > 2000 ? 5 : 15

        return Chart {
            ForEach(glucose) { item in
                if item.glucose > Int(highLimit) {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.orange.gradient).symbolSize(size).interpolationMethod(.cardinal)
                } else if item.glucose < Int(lowLimit) {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.red.gradient).symbolSize(size).interpolationMethod(.cardinal)
                } else {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.green.gradient).symbolSize(size).interpolationMethod(.cardinal)
                }
            }
        }
        .chartYAxis {
            AxisMarks(
                values: [
                    0,
                    low,
                    high,
                    units == .mmolL ? 15 : 270
                ]
            )
        }
    }

    var tirChart: some View {
        let fetched = tir()
        let low = lowLimit * conversionFactor
        let high = highLimit * conversionFactor

        let data: [ShapeModel] = [
            .init(
                type: NSLocalizedString(
                    "Low",
                    comment: ""
                ) + " (<\(low.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))))",
                percent: fetched[0].decimal
            ),
            .init(type: NSLocalizedString("In Range", comment: ""), percent: fetched[1].decimal),
            .init(
                type: NSLocalizedString(
                    "High",
                    comment: ""
                ) + " (>\(high.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))))",
                percent: fetched[2].decimal
            )
        ]
        return Chart(data) { shape in
            BarMark(
                x: .value("TIR", shape.percent)
            )
            .foregroundStyle(by: .value("Group", shape.type))
            .annotation(position: .top, alignment: .center) {
                Text(
                    "\(shape.percent, format: .number.precision(.fractionLength(0))) %"
                ).font(.footnote).foregroundColor(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .chartForegroundStyleScale([
            NSLocalizedString(
                "Low",
                comment: ""
            ) + " (<\(low.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))))": .red,
            NSLocalizedString("In Range", comment: ""): .green,
            NSLocalizedString(
                "High",
                comment: ""
            ) + " (>\(high.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))))": .orange
        ]).frame(maxHeight: 25)
    }

    var standingTIRchart: some View {
        let fetched = tir()
        let low = lowLimit * conversionFactor
        let high = highLimit * conversionFactor
        let fraction = units == .mmolL ? 1 : 0
        let data: [ShapeModel] = [
            .init(
                type: NSLocalizedString(
                    "Low",
                    comment: ""
                ) + " (< \(low.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))))",
                percent: fetched[0].decimal
            ),
            .init(
                type: "\(low.formatted(.number.precision(.fractionLength(fraction)))) - \(high.formatted(.number.precision(.fractionLength(fraction))))",
                percent: fetched[1].decimal
            ),
            .init(
                type: NSLocalizedString(
                    "High",
                    comment: ""
                ) + " (> \(high.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))))",
                percent: fetched[2].decimal
            )
        ]
        return Chart(data) { shape in
            BarMark(
                x: .value("Shape", shape.type),
                y: .value("Percentage", shape.percent)
            )
            .foregroundStyle(by: .value("Group", shape.type))
            .annotation(position: shape.percent > 19 ? .overlay : .automatic, alignment: .center) {
                Text(shape.percent == 0 ? "" : "\(shape.percent, format: .number.precision(.fractionLength(0)))")
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(
                format: Decimal.FormatStyle.Percent.percent.scale(1)
            )
        }
        .chartForegroundStyleScale([
            NSLocalizedString(
                "Low",
                comment: ""
            ) + " (< \(low.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))))": .red,
            "\(low.formatted(.number.precision(.fractionLength(fraction)))) - \(high.formatted(.number.precision(.fractionLength(fraction))))": .green,
            NSLocalizedString(
                "High",
                comment: ""
            ) + " (> \(high.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))))": .orange
        ])
    }

    var groupedGlucose: some View {
        VStack(alignment: .leading, spacing: 20) {
            let mapGlucose = glucose.compactMap({ each in each.glucose })
            if !mapGlucose.isEmpty {
                let mapGlucoseAcuteLow = mapGlucose.filter({ $0 < Int16(3.3 / 0.0555) })
                let mapGlucoseHigh = mapGlucose.filter({ $0 > Int16(11 / 0.0555) })
                let mapGlucoseNormal = mapGlucose.filter({ $0 > Int16(3.8 / 0.0555) && $0 < Int16(7.9 / 0.0555) })
                HStack {
                    let value = Double(mapGlucoseHigh.count * 100 / mapGlucose.count)
                    Text(units == .mmolL ? ">  11  " : ">  198 ").foregroundColor(.secondary)
                    Text(value.formatted()).foregroundColor(.orange)
                    Text("%").foregroundColor(.secondary)
                }.font(.caption)
                HStack {
                    let value = Double(mapGlucoseNormal.count * 100 / mapGlucose.count)
                    Text(units == .mmolL ? "3.9-7.8" : "70-140").foregroundColor(.secondary)
                    Text(value.formatted()).foregroundColor(.green)
                    Text("%").foregroundColor(.secondary)
                }.font(.caption)
                HStack {
                    let value = Double(mapGlucoseAcuteLow.count * 100 / mapGlucose.count)
                    Text(units == .mmolL ? "<  3.3 " : "<  59  ").foregroundColor(.secondary)
                    Text(value.formatted()).foregroundColor(.red)
                    Text("%").foregroundColor(.secondary)
                }.font(.caption)
            }
        }
    }

    var groupedGlucoseStatsLaying: some View {
        HStack {
            let mapGlucose = glucose.compactMap({ each in each.glucose })
            if !mapGlucose.isEmpty {
                let mapGlucoseLow = mapGlucose.filter({ $0 < Int16(3.3 / 0.0555) })
                let mapGlucoseNormal = mapGlucose.filter({ $0 > Int16(3.8 / 0.0555) && $0 < Int16(7.9 / 0.0555) })
                let mapGlucoseAcuteHigh = mapGlucose.filter({ $0 > Int16(11 / 0.0555) })
                HStack {
                    let value = Double(mapGlucoseLow.count * 100 / mapGlucose.count)
                    Text(units == .mmolL ? "< 3.3" : "< 59").font(.caption2).foregroundColor(.secondary)
                    Text(value.formatted()).font(.caption).foregroundColor(value == 0 ? .green : .red)
                    Text("%").font(.caption)
                }
                Spacer()
                HStack {
                    let value = Double(mapGlucoseNormal.count * 100 / mapGlucose.count)
                    Text(units == .mmolL ? "3.9-7.8" : "70-140").foregroundColor(.secondary)
                    Text(value.formatted()).foregroundColor(.green)
                    Text("%").foregroundColor(.secondary)
                }.font(.caption)
                Spacer()
                HStack {
                    let value = Double(mapGlucoseAcuteHigh.count * 100 / mapGlucose.count)
                    Text(units == .mmolL ? "> 11.0" : "> 198").font(.caption).foregroundColor(.secondary)
                    Text(value.formatted()).font(.caption).foregroundColor(value == 0 ? .green : .orange)
                    Text("%").font(.caption)
                }
            }
        }
    }

    private func tir() -> [(decimal: Decimal, string: String)] {
        let hypoLimit = Int(lowLimit)
        let hyperLimit = Int(highLimit)

        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let totalReadings = justGlucoseArray.count

        let hyperArray = glucose.filter({ $0.glucose > hyperLimit })
        let hyperReadings = hyperArray.compactMap({ each in each.glucose as Int16 }).count
        let hyperPercentage = Double(hyperReadings) / Double(totalReadings) * 100

        let hypoArray = glucose.filter({ $0.glucose < hypoLimit })
        let hypoReadings = hypoArray.compactMap({ each in each.glucose as Int16 }).count
        let hypoPercentage = Double(hypoReadings) / Double(totalReadings) * 100

        let tir = 100 - (hypoPercentage + hyperPercentage)

        var array: [(decimal: Decimal, string: String)] = []
        array.append((decimal: Decimal(hypoPercentage), string: "Low"))
        array.append((decimal: Decimal(tir), string: "NormaL"))
        array.append((decimal: Decimal(hyperPercentage), string: "High"))

        return array
    }
}

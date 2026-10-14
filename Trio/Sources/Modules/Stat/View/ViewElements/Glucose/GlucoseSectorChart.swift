import Charts
import SwiftUI

struct GlucoseSectorChart: View, Equatable {
    private typealias RangeData = [(range: GlucoseRange, count: Int, color: Color)]

    let highLimit: Decimal
    let units: GlucoseUnits
    let glucose: [GlucoseReading]
    let timeInRangeType: TimeInRangeType
    let showChart: Bool

    @State private var selectedCount: Int?
    @State private var selectedRange: GlucoseRange?

    static func == (lhs: GlucoseSectorChart, rhs: GlucoseSectorChart) -> Bool {
        lhs.highLimit == rhs.highLimit && lhs.units == rhs.units && lhs.glucose == rhs.glucose &&
            lhs.timeInRangeType == rhs.timeInRangeType && lhs.showChart == rhs.showChart
    }

    private enum GlucoseRange {
        case high
        case inRange
        case low
    }

    private func bandRow(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(value)
                .foregroundStyle(color)
        }
    }

    private func infoFor(_ band: GlucoseBand) -> (label: String, color: Color) {
        StatChartUtils.glucoseBandDisplayInfo(for: band, units: units, timeInRangeType: timeInRangeType, highLimit: highLimit)
    }

    private func shareOf(_ count: Int) -> Decimal {
        Decimal(count) / Decimal(glucose.count) * 100
    }

    var body: some View {
        if glucose.isEmpty {
            Text("No glucose readings found.")
        } else {
            let grouped = Dictionary(grouping: glucose) { reading in
                GlucoseBand.classify(
                    reading.value,
                    bottom: timeInRangeType.bottomThreshold,
                    top: timeInRangeType.topThreshold,
                    highLimit: Int(highLimit)
                )
            }

            let chartData = makeRangeData(from: grouped)
            HStack(alignment: .center, spacing: 20) {
                let high = grouped[.high]?.count ?? 0
                let tight = grouped[.tight]?.count ?? 0
                let upperMid = grouped[.upperMid]?.count ?? 0
                let low = grouped[.low]?.count ?? 0
                let veryLow = grouped[.veryLow]?.count ?? 0
                let veryHigh = grouped[.veryHigh]?.count ?? 0

                VStack(alignment: .leading, spacing: 10) {
                    let veryLowInfo = infoFor(.veryLow)
                    let upperMidInfo = infoFor(.upperMid)
                    bandRow(
                        label: veryLowInfo.label,
                        value: StatChartUtils.formatPercentage(shareOf(veryLow)),
                        color: veryLowInfo.color
                    )
                    bandRow(
                        label: upperMidInfo.label,
                        value: StatChartUtils.formatPercentage(shareOf(upperMid)),
                        color: upperMidInfo.color
                    )

                }.padding(.leading, 5)

                VStack(alignment: .leading, spacing: 10) {
                    let lowInfo = infoFor(.low)
                    let highInfo = infoFor(.high)
                    bandRow(
                        label: lowInfo.label,
                        value: StatChartUtils.formatPercentage(shareOf(low)),
                        color: lowInfo.color
                    )
                    bandRow(
                        label: highInfo.label,
                        value: StatChartUtils.formatPercentage(shareOf(high)),
                        color: highInfo.color
                    )
                }.padding(.leading, 5)
                VStack(alignment: .leading, spacing: 10) {
                    let tightInfo = infoFor(.tight)
                    let veryHighInfo = infoFor(.veryHigh)
                    bandRow(
                        label: tightInfo.label,
                        value: StatChartUtils.formatPercentage(shareOf(tight)),
                        color: tightInfo.color
                    )
                    bandRow(
                        label: veryHighInfo.label,
                        value: StatChartUtils.formatPercentage(shareOf(veryHigh)),
                        color: veryHighInfo.color
                    )
                }.padding(.leading, 5)

                if !showChart {
                    let summary = StatChartUtils.summaryStats(for: glucose.map(\.value))

                    VStack(alignment: .leading, spacing: 10) {
                        bandRow(
                            label: "Average",
                            value: summary.average.formattedAsGlucose(for: units),
                            color: .primary
                        )
                        bandRow(
                            label: "Median",
                            value: summary.median.formattedAsGlucose(for: units),
                            color: .primary
                        )
                    }.padding(.leading, 5)

                } else {
                    Chart {
                        ForEach(chartData, id: \.range) { data in
                            SectorMark(
                                angle: .value("Percentage", data.count),
                                innerRadius: .ratio(0.618),
                                outerRadius: selectedRange == data.range ? 100 : 80
                            )
                            .foregroundStyle(data.color)
                            .opacity(selectedRange == nil || selectedRange == data.range ? 1 : 0.3)
                        }
                    }
                    .chartAngleSelection(value: $selectedCount)
                    .frame(height: 100)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Time in range distribution chart"))
                }
            }
            .onChange(of: selectedCount) { _, newValue in
                selectedRange = newValue.flatMap { getSelectedRange(for: $0, in: chartData) }
            }
            .overlay(alignment: .top) {
                if let selectedRange {
                    let data = getDetailedData(for: selectedRange, from: grouped)
                    RangeDetailPopover(data: data)
                        .offset(y: -150) // TODO: make this dynamic
                }
            }
        }
    }

    private func makeRangeData(from grouped: [GlucoseBand: [GlucoseReading]]) -> RangeData {
        let lowCount = (grouped[.low]?.count ?? 0) + (grouped[.veryLow]?.count ?? 0)
        let inRangeCount = (grouped[.tight]?.count ?? 0) + (grouped[.upperMid]?.count ?? 0)
        let highCount = (grouped[.high]?.count ?? 0) + (grouped[.veryHigh]?.count ?? 0)

        return [
            (.high, highCount, .dynamicPurple),
            (.inRange, inRangeCount, .dynamicGreen),
            (.low, lowCount, .dynamicRed)
        ]
    }

    private func getSelectedRange(for value: Int, in data: RangeData) -> GlucoseRange? {
        var cumulativeTotal = 0
        for entry in data {
            cumulativeTotal += entry.count
            if value <= cumulativeTotal { return entry.range }
        }
        return nil
    }

    private func getDetailedData(
        for range: GlucoseRange,
        from grouped: [GlucoseBand: [GlucoseReading]]
    ) -> RangeDetail {
        switch range {
        case .high:
            let veryHigh = grouped[.veryHigh]?.count ?? 0
            let high = grouped[.high]?.count ?? 0

            let highGlucoseValues = ((grouped[.high] ?? []) + (grouped[.veryHigh] ?? [])).map(\.value)
            let summary = StatChartUtils.summaryStats(for: highGlucoseValues)

            return RangeDetail(
                title: String(localized: "High Glucose"),
                color: .dynamicPurple,
                percentages: [
                    (
                        String(localized: "Very High (\(infoFor(.veryHigh).label))"),
                        StatChartUtils.formatPercentage(shareOf(veryHigh))
                    ),
                    (
                        String(localized: "High (\(infoFor(.high).label))"),
                        StatChartUtils.formatPercentage(shareOf(high))
                    )
                ],
                statistics: [
                    (String(localized: "Average"), summary.average.formattedAsGlucose(for: units)),
                    (String(localized: "Median"), summary.median.formattedAsGlucose(for: units)),
                    (String(localized: "SD"), summary.standardDeviation.formattedAsGlucose(for: units))
                ]
            )

        case .inRange:
            let tight = grouped[.tight]?.count ?? 0
            let upperMid = grouped[.upperMid]?.count ?? 0
            let glucoseValues = ((grouped[.tight] ?? []) + (grouped[.upperMid] ?? [])).map(\.value)

            let summary = StatChartUtils.summaryStats(for: glucoseValues)

            return RangeDetail(
                title: String(localized: "In Range"),
                color: .dynamicGreen,
                percentages: [
                    (
                        String(
                            localized: "Normal (\(infoFor(.upperMid).label))"
                        ),
                        StatChartUtils.formatPercentage(shareOf(upperMid))
                    ),
                    (
                        String(
                            localized: "\(timeInRangeType == .timeInTightRange ? "TITR" : "TING") (\(infoFor(.tight).label))"
                        ),
                        StatChartUtils.formatPercentage(shareOf(tight))
                    )
                ],
                statistics: [
                    (String(localized: "Average"), summary.average.formattedAsGlucose(for: units)),
                    (String(localized: "Median"), summary.median.formattedAsGlucose(for: units)),
                    (String(localized: "SD"), summary.standardDeviation.formattedAsGlucose(for: units))
                ]
            )

        case .low:
            let veryLow = grouped[.veryLow]?.count ?? 0
            let low = grouped[.low]?.count ?? 0

            let lowGlucoseValues = ((grouped[.veryLow] ?? []) + (grouped[.low] ?? [])).map(\.value)
            let summary = StatChartUtils.summaryStats(for: lowGlucoseValues)

            return RangeDetail(
                title: String(localized: "Low Glucose"),
                color: .dynamicRed,
                percentages: [
                    (
                        String(
                            localized: "Low (\(infoFor(.low).label))"
                        ),
                        StatChartUtils.formatPercentage(shareOf(low))
                    ),
                    (
                        String(localized: "Very Low (\(infoFor(.veryLow).label))"),
                        StatChartUtils.formatPercentage(shareOf(veryLow))
                    )
                ],
                statistics: [
                    (String(localized: "Average"), summary.average.formattedAsGlucose(for: units)),
                    (String(localized: "Median"), summary.median.formattedAsGlucose(for: units)),
                    (String(localized: "SD"), summary.standardDeviation.formattedAsGlucose(for: units))
                ]
            )
        }
    }
}

private struct RangeDetail {
    let title: String
    let color: Color
    let percentages: [(label: String, value: String)]
    let statistics: [(label: String, value: String)]
}

private struct RangeDetailPopover: View {
    let data: RangeDetail

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(data.title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(data.color)
                .padding(.bottom, 4)

            ForEach(data.percentages, id: \.label) { item in
                HStack {
                    Text(item.label)
                    Text(item.value).bold()
                }
                .font(.footnote)
            }

            HStack(spacing: 20) {
                ForEach(data.statistics, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.label)
                        Text(item.value).bold()
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.bgDarkBlue.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(data.color, lineWidth: 2)
                )
        }
    }
}

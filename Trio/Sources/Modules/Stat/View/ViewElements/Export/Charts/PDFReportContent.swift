import SwiftUI

/// PDF page content for the "Glucose Distribution" export.
/// Reuses the same chart/stat components shown in the on-screen Statistics sheet.
struct GlucoseDistributionPDFContent: View {
    let glucose: [GlucoseStored]
    let glucoseRangeStats: [GlucoseRangeStats]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit
    let timeInRangeType: TimeInRangeType

    var body: some View {
        GlucoseDistributionChart(
            glucose: glucose,
            highLimit: highLimit,
            lowLimit: lowLimit,
            units: units,
            glucoseRangeStats: glucoseRangeStats,
            timeInRangeType: timeInRangeType
        )

        Divider()

        VStack(spacing: 16) {
            GlucoseSectorChart(
                highLimit: highLimit,
                units: units,
                glucose: glucose,
                timeInRangeType: timeInRangeType,
                showChart: true
            )

            Divider()

            GlucoseMetricsView(
                units: units,
                eA1cDisplayUnit: eA1cDisplayUnit,
                glucose: glucose
            )
        }
    }
}

/// PDF page content for the "Glucose Percentile" (AGP) export.
/// Reuses the same AGP chart shown in the on-screen Statistics sheet.
struct GlucosePercentilePDFContent: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let timeInRangeType: TimeInRangeType
    let units: GlucoseUnits
    let hourlyStats: [HourlyStats]

    var body: some View {
        GlucosePercentileChart(
            glucose: glucose,
            highLimit: highLimit,
            timeInRangeType: timeInRangeType,
            units: units,
            hourlyStats: hourlyStats,
            isToday: false
        )
    }
}

/// PDF page content for the "Looping Performance" export.
/// Reuses the same static bar chart and stats row shown in the on-screen Statistics sheet.
struct LoopingPerformancePDFContent: View {
    let loopStatRecords: [LoopStatRecord]
    let selectedInterval: Stat.StateModel.StatsTimeIntervalWithToday
    let loopStats: [LoopStatsProcessedData]

    var body: some View {
        LoopBarChartView(
            loopStatRecords: loopStatRecords,
            selectedInterval: selectedInterval,
            statsData: loopStats
        )

        Divider()

        LoopStatsView(statsData: loopStats)
    }
}

/// PDF page content for the "Glycemia Risk Index" export.
/// Reuses the GRI risk grid and score colors from the on-screen Statistics sheet, laid out
/// statically (no sheet or disclosure group) so the full breakdown fits on one page.
struct GlycemiaRiskIndexPDFContent: View {
    let result: GRICalculator.Result?
    let units: GlucoseUnits

    var body: some View {
        if let result {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("GRI")
                        .font(.headline)
                    Text(result.score, format: .number.precision(.fractionLength(1)))
                        .font(.largeTitle.bold())
                    Text("/ 100")
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Text("Zone \(result.zone)")
                        .font(.headline)
                        .foregroundStyle(griColor(result.score))
                }

                HStack(alignment: .top, spacing: 20) {
                    GRIRiskGridView(result: result)
                        .frame(width: 260)

                    breakdown(result)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Glycemia Risk Index combines low and high glucose exposure into a score from 0 to 100. Lower scores indicate less glycemic risk."
                    )
                    Text("GRI uses fixed glucose thresholds, regardless of your target range or display units.")
                    Text("The final GRI score is capped at 100. Calculations use unrounded values.")
                    Text(
                        "Calculated from glucose readings in the selected period. Short periods and gaps in sensor data can make the score less representative."
                    )
                }
                .font(.caption)
                .foregroundStyle(Color.secondary)
            }
        } else {
            ContentUnavailableView("No Glucose Data", systemImage: "chart.bar.fill")
        }
    }

    private func breakdown(_ result: GRICalculator.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Below \(54.formatted(withUnits: units))", percentage(result.veryLowPercentage), GRICalculationColors.veryLow)
            row(
                "\(54.formatted(for: units)) to below \(70.formatted(withUnits: units))",
                percentage(result.lowPercentage),
                GRICalculationColors.low
            )
            row(
                "Above \(180.formatted(for: units)) through \(250.formatted(withUnits: units))",
                percentage(result.highPercentage),
                GRICalculationColors.high
            )
            row("Above \(250.formatted(withUnits: units))", percentage(result.veryHighPercentage), GRICalculationColors.veryHigh)

            Divider()

            row("Hypoglycemia component", component(result.hypoComponent), GRICalculationColors.hypo)
            row("Hyperglycemia component", component(result.hyperComponent), GRICalculationColors.hyper)

            Divider()

            formula(
                "Weighted hypoglycemia",
                "3 × \(number(result.hypoComponent)) = \(number(result.weightedHypoComponent))",
                GRICalculationColors.hypo
            )
            formula(
                "Weighted hyperglycemia",
                "\(number(1.6)) × \(number(result.hyperComponent)) = \(number(result.weightedHyperComponent))",
                GRICalculationColors.hyper
            )
            formula(
                "Combined score",
                "\(number(result.weightedHypoComponent)) + \(number(result.weightedHyperComponent)) = \(number(result.uncappedScore))",
                Color.black
            )
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }

    private func formula(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(verbatim: value)
                .monospacedDigit()
        }
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func component(_ value: Double) -> String {
        number(value) + "%"
    }

    private func percentage(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(1)))
    }
}

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

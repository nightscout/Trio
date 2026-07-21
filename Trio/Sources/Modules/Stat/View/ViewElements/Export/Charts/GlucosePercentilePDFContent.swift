import SwiftUI

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

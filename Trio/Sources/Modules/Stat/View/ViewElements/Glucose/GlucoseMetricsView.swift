import SwiftUI

struct GlucoseMetricsView: View, Equatable {
    let units: GlucoseUnits
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit
    let glucose: [GlucoseReading]

    var body: some View {
        let preferredUnit: GlucoseUnits = eA1cDisplayUnit == .mmolMol ? .mmolL : .mgdL

        let dates = glucose.map(\.date)
        let earliestDate = dates.min() ?? Date()
        let latestDate = dates.max() ?? Date()
        let totalDays = latestDate.timeIntervalSince(earliestDate) / 86400

        let glucoseStats = calculateGlucoseStatistics(totalDays: totalDays)

        let eA1cString = preferredUnit == .mgdL
            ? StatChartUtils.formatPercentage(glucoseStats.ngsp)
            : glucoseStats.ifcc.formatted(.number.grouping(.never).precision(.fractionLength(1)))

        let gmiString = preferredUnit == .mgdL
            ? StatChartUtils.formatPercentage(glucoseStats.gmiPercentage)
            : glucoseStats.gmiMmolMol.formatted(.number.grouping(.never).precision(.fractionLength(1)))

        let standardDeviationString = glucoseStats.sd.formattedAsGlucose(for: units)
        let coefficientOfVariationString = StatChartUtils.formatPercentage(glucoseStats.cv)
        let daysTrackedString = totalDays.formatted(.number.grouping(.never).precision(.fractionLength(1)))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatChartUtils.statView(title: String(localized: "eA1c"), value: eA1cString)
                Spacer()
                StatChartUtils.statView(title: String(localized: "GMI"), value: gmiString)
                Spacer()
                StatChartUtils.statView(title: String(localized: "SD"), value: standardDeviationString)
                Spacer()
                StatChartUtils.statView(title: String(localized: "CV"), value: coefficientOfVariationString)
                Spacer()
                StatChartUtils.statView(title: String(localized: "Days"), value: daysTrackedString)
            }
        }
    }

    func calculateGlucoseStatistics(totalDays: Double) -> (
        ifcc: Double, ngsp: Double, gmiMmolMol: Double, gmiPercentage: Double, sd: Double, cv: Double
    ) {
        let glucoseValues = glucose.map(\.value)

        guard glucoseValues.isNotEmpty else {
            return (ifcc: 0, ngsp: 0, gmiMmolMol: 0, gmiPercentage: 0, sd: 0, cv: 0)
        }
        let (average, _, standardDeviation) = StatChartUtils.summaryStats(for: glucoseValues)

        // Standard eA1c/GMI equations (Nathan, Bergenstal); average in mg/dL.
        var eA1cNGSP = 0.0
        var eA1cIFCC = 0.0
        var gmiValuePercentage = 0.0
        var gmiValueMmolMol = 0.0

        if totalDays > 0 {
            // eA1c NGSP (%) = (avg + 46.7) / 28.7
            eA1cNGSP = (average + 46.7) / 28.7

            // eA1c IFCC (mmol/mol) = 10.929 * (NGSP - 2.152)
            eA1cIFCC = 10.929 * (eA1cNGSP - 2.152)

            // GMI (%) = 3.31 + 0.02392 * avg
            gmiValuePercentage = 3.31 + (0.02392 * average)

            // GMI (mmol/mol) = (GMI% - 2.152) * 10.929
            gmiValueMmolMol = (gmiValuePercentage - 2.152) * 10.929
        }

        let coefficientOfVariation = (average > 0) ? (standardDeviation / average) * 100 : 0.0

        return (
            ifcc: eA1cIFCC,
            ngsp: eA1cNGSP,
            gmiMmolMol: gmiValueMmolMol,
            gmiPercentage: gmiValuePercentage,
            sd: standardDeviation,
            cv: coefficientOfVariation
        )
    }
}

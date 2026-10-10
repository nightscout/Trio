import SwiftUI

/// A SwiftUI view displaying various glucose-related statistics based on stored glucose readings.
struct GlucoseMetricsView: View, Equatable {
    /// The unit of measurement for blood glucose values (e.g., mg/dL or mmol/L).
    let units: GlucoseUnits
    /// The display unit for estimated HbA1c values.
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit
    /// A list of stored glucose readings.
    let glucose: [GlucoseReading]

    /// The main body of the `GlucoseMetricsView`, displaying glucose-related statistics.
    var body: some View {
        let preferredUnit: GlucoseUnits = eA1cDisplayUnit == .mmolMol ? .mmolL : .mgdL

        let dates = glucose.map(\.date)
        // Determine the date range of the glucose data
        let earliestDate = dates.min() ?? Date()
        let latestDate = dates.max() ?? Date()
        let totalDays = latestDate.timeIntervalSince(earliestDate) / 86400

        let glucoseStats = calculateGlucoseStatistics(totalDays: totalDays)

        // Format glucose statistics based on the selected unit
        let eA1cString = preferredUnit == .mgdL
            ? StatChartUtils.formatPercentage(glucoseStats.ngsp)
            : glucoseStats.ifcc.formatted(.number.grouping(.never).precision(.fractionLength(1)))

        let gmiString = preferredUnit == .mgdL
            ? StatChartUtils.formatPercentage(glucoseStats.gmiPercentage)
            : glucoseStats.gmiMmolMol.formatted(.number.grouping(.never).precision(.fractionLength(1)))

        // glucoseStats already parsed to units - only format decimals
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

    /// Computes various statistical metrics from stored glucose readings, including:
    /// - Estimated A1c in NGSP (%) and IFCC (mmol/mol)
    /// - Glucose Management Index (GMI) in both mmol/mol and percentage
    /// - Average and median glucose levels
    /// - Standard deviation (SD) and coefficient of variation (CV)
    /// - Number of readings per day
    ///
    /// - Returns: A tuple containing glucose statistics.
    func calculateGlucoseStatistics(totalDays: Double) -> (
        ifcc: Double, ngsp: Double, gmiMmolMol: Double, gmiPercentage: Double, sd: Double, cv: Double
    ) {
        let glucoseValues = glucose.map(\.value)

        // Handle empty dataset case
        guard glucoseValues.isNotEmpty else {
            return (ifcc: 0, ngsp: 0, gmiMmolMol: 0, gmiPercentage: 0, sd: 0, cv: 0)
        }
        let (average, _, standardDeviation) = StatChartUtils.summaryStats(for: glucoseValues)

        // Estimated A1c and Glucose Management Index (GMI) calculations
        var eA1cNGSP = 0.0 // eA1c NGSP (%)
        var eA1cIFCC = 0.0 // eA1c IFCC (mmol/mol)
        var gmiValuePercentage = 0.0 // GMI (%)
        var gmiValueMmolMol = 0.0 // GMI (mmol/mol)

        if totalDays > 0 {
            // **eA1c NGSP Calculation** (CGM-based)
            // eA1c NGSP (%) = (Average Glucose mg/dL + 46.7) / 28.7
            eA1cNGSP = (average + 46.7) / 28.7

            // **eA1c IFCC Calculation**
            // eA1c IFCC (mmol/mol) = 10.929 * (eA1c NGSP - 2.152)
            eA1cIFCC = 10.929 * (eA1cNGSP - 2.152)

            // **Glucose Management Index (GMI) in %**
            // GMI = 3.31 + (0.02392 × Average Glucose mg/dL)
            gmiValuePercentage = 3.31 + (0.02392 * average)

            // **Glucose Management Index (GMI) in mmol/mol**
            // GMI mmol/mol = (GMI % - 2.15) * 10.929
            gmiValueMmolMol = (gmiValuePercentage - 2.152) * 10.929
        }

        let coefficientOfVariation = (average > 0) ? (standardDeviation / average) * 100 : 0.0

        return (
            ifcc: eA1cIFCC, // eA1c in IFCC (mmol/mol)
            ngsp: eA1cNGSP, // eA1c in NGSP (%)
            gmiMmolMol: gmiValueMmolMol, // GMI in mmol/mol
            gmiPercentage: gmiValuePercentage, // GMI in %
            sd: standardDeviation,
            cv: coefficientOfVariation // CV is already in percentage format
        )
    }
}

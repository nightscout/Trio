import CoreData
import SwiftDate
import SwiftUI

/// A SwiftUI view displaying various glucose-related statistics based on stored glucose readings.
struct GlucoseMetricsView: View {
    /// The unit of measurement for blood glucose values (e.g., mg/dL or mmol/L).
    let units: GlucoseUnits
    /// The display unit for estimated HbA1c values.
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit
    /// A list of stored glucose readings.
    let glucose: [GlucoseStored]

    /// The main body of the `GlucoseMetricsView`, displaying glucose-related statistics.
    var body: some View {
        let preferredUnit: GlucoseUnits = eA1cDisplayUnit == .mmolMol ? .mmolL : .mgdL

        let glucoseStats = calculateGlucoseStatistics()

        // Determine the time range of the stored glucose data
        let earliestDate = glucose.last?.date ?? Date()
        let latestDate = glucose.first?.date ?? Date()
        let totalDays = (latestDate - earliestDate).timeInterval / 86400

        // Format glucose statistics based on the selected unit
        let eA1cString = preferredUnit == .mgdL
            ? (glucoseStats.ngsp.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "%") : glucoseStats
            .ifcc.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))

        let gmiString = preferredUnit == .mgdL ?
            (glucoseStats.gmiPercentage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "%") :
            glucoseStats.gmiMmolMol.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))

        // glucoseStats already parsed to units - only format decimals
        let standardDeviationString = units == .mgdL ? glucoseStats.sd.formatted(
            .number.grouping(.never).rounded().precision(.fractionLength(0))
        ) : glucoseStats.sd.formatted(
            .number.grouping(.never).rounded().precision(.fractionLength(1))
        )
        let coefficientOfVariationString = glucoseStats.cv
            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "%"
        let daysTrackedString = totalDays.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))

        VStack(alignment: .leading) {
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
    func calculateGlucoseStatistics() -> (
        ifcc: Double, ngsp: Double, gmiMmolMol: Double, gmiPercentage: Double, average: Double,
        median: Double, sd: Double, cv: Double, readingsPerDay: Double
    ) {
        // Determine the date range of the glucose data
        let earliestDate = glucose.last?.date ?? Date()
        let latestDate = glucose.first?.date ?? Date()
        let totalDays = latestDate.timeIntervalSince(earliestDate) / 86400

        // Ensure at least one day to avoid division by zero
        let daysCount = max(totalDays, 1)

        // Extract glucose values as an array of integers
        let glucoseValues = glucose.compactMap { Int($0.glucose as Int16) }
        let totalReadings = glucoseValues.count

        // Handle empty dataset case
        guard totalReadings > 1 else {
            return (ifcc: 0, ngsp: 0, gmiMmolMol: 0, gmiPercentage: 0, average: 0, median: 0, sd: 0, cv: 0, readingsPerDay: 0)
        }

        let sumOfReadings = glucoseValues.reduce(0, +)
        // Compute mean (average) glucose level
        let meanGlucose = Double(sumOfReadings) / Double(totalReadings)
        // Compute median glucose level
        let medianGlucose = StatChartUtils.medianCalculation(array: glucoseValues)

        // Estimated A1c and Glucose Management Index (GMI) calculations
        var eA1cNGSP = 0.0 // eA1c NGSP (%)
        var eA1cIFCC = 0.0 // eA1c IFCC (mmol/mol)
        var gmiValuePercentage = 0.0 // GMI (%)
        var gmiValueMmolMol = 0.0 // GMI (mmol/mol)

        if totalDays > 0 {
            // **eA1c NGSP Calculation** (CGM-based)
            // eA1c NGSP (%) = (Average Glucose mg/dL + 46.7) / 28.7
            eA1cNGSP = (meanGlucose + 46.7) / 28.7

            // **eA1c IFCC Calculation**
            // eA1c IFCC (mmol/mol) = 10.929 * (eA1c NGSP - 2.152)
            eA1cIFCC = 10.929 * (eA1cNGSP - 2.152)

            // **Glucose Management Index (GMI) in %**
            // GMI = 3.31 + (0.02392 × Average Glucose mg/dL)
            gmiValuePercentage = 3.31 + (0.02392 * meanGlucose)

            // **Glucose Management Index (GMI) in mmol/mol**
            // GMI mmol/mol = (GMI % - 2.15) * 10.929
            gmiValueMmolMol = (gmiValuePercentage - 2.152) * 10.929
        }

        // Compute Standard Deviation (SD) and Coefficient of Variation (CV)
        let sumOfSquaredDifferences = glucoseValues.reduce(0.0) { sum, value in
            sum + pow(Double(value) - meanGlucose, 2)
        }

        let standardDeviation = sqrt(sumOfSquaredDifferences / Double(totalReadings - 1)) // Using N-1 for sample SD
        let coefficientOfVariation = (meanGlucose > 0) ? (standardDeviation / meanGlucose) * 100 : 0.0

        return (
            ifcc: eA1cIFCC, // eA1c in IFCC (mmol/mol)
            ngsp: eA1cNGSP, // eA1c in NGSP (%)
            gmiMmolMol: gmiValueMmolMol, // GMI in mmol/mol
            gmiPercentage: gmiValuePercentage, // GMI in %
            average: Double(units == .mgdL ? Decimal(meanGlucose) : meanGlucose.asMmolL),
            median: Double(units == .mgdL ? Decimal(medianGlucose) : medianGlucose.asMmolL),
            sd: Double(units == .mgdL ? Decimal(standardDeviation) : standardDeviation.asMmolL),
            cv: coefficientOfVariation, // CV is already in percentage format
            readingsPerDay: Double(totalReadings) / Double(daysCount)
        )
    }
}

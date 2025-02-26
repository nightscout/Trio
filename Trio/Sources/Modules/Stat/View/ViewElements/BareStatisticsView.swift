import CoreData
import SwiftDate
import SwiftUI

struct BareStatisticsView {
    // MARK: - Helper Functions

    static func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }

    static func medianCalculationDouble(array: [Double]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    struct GlucoseMetricsView: View {
        let highLimit: Decimal
        let lowLimit: Decimal
        let units: GlucoseUnits
        let eA1cDisplayUnit: EstimatedA1cDisplayUnit
        let glucose: [GlucoseStored]

        var body: some View {
            VStack(alignment: .leading) {
                HStack(spacing: 40) {
                    let useUnit: GlucoseUnits = {
                        if eA1cDisplayUnit == .mmolMol { return .mmolL }
                        else { return .mgdL }
                    }()

                    let glucoseStats = calculateGlucoseStatistics()
                    // First date
                    let previous = glucose.last?.date ?? Date()
                    // Last date (recent)
                    let current = glucose.first?.date ?? Date()
                    // Total time in days
                    let numberOfDays = (current - previous).timeInterval / 8.64E4

                    let eA1cString = (
                        useUnit == .mmolL ? glucoseStats.ifcc
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) : glucoseStats.ngsp
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                            + "%"
                    )
                    VStack(spacing: 5) {
                        Text("eA1c").font(.subheadline).foregroundColor(.secondary)
                        Text(eA1cString)
                    }
                    VStack(spacing: 5) {
                        Text("GMI").font(.subheadline).foregroundColor(.secondary)
                        Text(glucoseStats.gmi.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "%")
                    }
                    VStack(spacing: 5) {
                        Text("SD").font(.subheadline).foregroundColor(.secondary)
                        Text(
                            glucoseStats.sd
                                .formatted(
                                    .number.grouping(.never).rounded()
                                        .precision(.fractionLength(units == .mmolL ? 1 : 0))
                                )
                        )
                    }
                    VStack(spacing: 5) {
                        Text("CV").font(.subheadline).foregroundColor(.secondary)
                        Text(glucoseStats.cv.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))))
                    }
                    VStack(spacing: 5) {
                        Text("Days").font(.subheadline).foregroundColor(.secondary)
                        Text(numberOfDays.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))))
                    }
                }
            }
        }

        func calculateGlucoseStatistics()
            -> (
                ifcc: Double,
                ngsp: Double,
                gmi: Double,
                average: Double,
                median: Double,
                sd: Double,
                cv: Double,
                readings: Double
            )
        {
            // First recorded glucose date
            let previous = glucose.last?.date ?? Date()
            // Most recent glucose date
            let current = glucose.first?.date ?? Date()
            // Total duration in days
            let numberOfDays = (current - previous).timeInterval / 8.64E4

            // Avoid division by zero, ensure at least 1 day
            let denominator = numberOfDays < 1 ? 1 : numberOfDays

            // Extract glucose values as an array of integers
            let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
            let sumReadings = justGlucoseArray.reduce(0, +)
            let countReadings = justGlucoseArray.count

            // Calculate the mean (average) glucose value
            let glucoseAverage = Double(sumReadings) / Double(countReadings)
            // Calculate the median glucose value
            let medianGlucose = BareStatisticsView.medianCalculation(array: justGlucoseArray)

            // Variables to store calculated values
            var eA1cNGSP = 0.0 // eA1c in NGSP (%) standard (CGM-based)
            var eA1cIFCC = 0.0 // eA1c in IFCC (mmol/mol) standard (CGM-based)
            var GMIValue = 0.0 // Glucose Management Index

            if numberOfDays > 0 {
                // **eA1c NGSP Calculation**: Estimated A1c in percentage (%)
                // Based on CGM readings, using the DCCT-derived formula:
                // eA1c NGSP (%) = (Average Glucose mg/dL + 46.7) / 28.7
                eA1cNGSP = (glucoseAverage + 46.7) / 28.7

                // **eA1c IFCC Calculation**: Conversion from eA1c NGSP to eA1c IFCC (mmol/mol)
                // eA1c IFCC (mmol/mol) = 10.929 * (eA1c NGSP - 2.152)
                // This conversion aligns with the IFCC standard.
                eA1cIFCC = 10.929 * (eA1cNGSP - 2.152)

                // **Glucose Management Index (GMI)**: Alternative eA1c estimate based on CGM data
                // GMI = 3.31 + (0.02392 × Average Glucose mg/dL)
                GMIValue = 3.31 + 0.02392 * glucoseAverage
            }

            // Calculate Standard Deviation (SD) and Coefficient of Variation (CV)
            var sumOfSquares = 0.0
            for value in justGlucoseArray {
                sumOfSquares += pow(Double(value) - glucoseAverage, 2)
            }

            var sd = 0.0
            var cv = 0.0

            if glucoseAverage > 0 {
                // Standard deviation: Measure of glucose variability
                sd = sqrt(sumOfSquares / Double(countReadings))
                // Coefficient of variation (CV %): Variability relative to mean glucose
                cv = sd / glucoseAverage * 100
            }

            return (
                ifcc: eA1cIFCC, // eA1c IFCC (mmol/mol)
                ngsp: eA1cNGSP, // eA1c NGSP (%)
                gmi: GMIValue, // Glucose Management Index
                average: glucoseAverage * (units == .mmolL ? 0.0555 : 1), // Convert if needed
                median: medianGlucose * (units == .mmolL ? 0.0555 : 1),
                sd: sd * (units == .mmolL ? 0.0555 : 1),
                cv: cv,
                readings: Double(countReadings) / denominator // Readings per day
            )
        }
    }

    struct BloodGlucoseView: View {
        let highLimit: Decimal
        let lowLimit: Decimal
        let units: GlucoseUnits
        let eA1cDisplayUnit: EstimatedA1cDisplayUnit
        let glucose: [GlucoseStored]

        var body: some View {
            bloodGlucose
        }

        private var bloodGlucose: some View {
            HStack(spacing: 30) {
                let bgs = glucoseStats()

                // First date
                let previous = glucose.last?.date ?? Date()
                // Last date (recent)
                let current = glucose.first?.date ?? Date()
                // Total time in days
                let numberOfDays = (current - previous).timeInterval / 8.64E4

                VStack(spacing: 5) {
                    Text(numberOfDays < 1 ? "Readings" : "Readings / 24h").font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(bgs.readings.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))))
                }
                VStack(spacing: 5) {
                    Text("Average").font(.subheadline).foregroundColor(.secondary)
                    Text(
                        bgs.average
                            .formatted(
                                .number.grouping(.never).rounded()
                                    .precision(.fractionLength(units == .mmolL ? 1 : 0))
                            )
                    )
                }
                VStack(spacing: 5) {
                    Text("Median").font(.subheadline).foregroundColor(.secondary)
                    Text(
                        bgs.median
                            .formatted(
                                .number.grouping(.never).rounded()
                                    .precision(.fractionLength(units == .mmolL ? 1 : 0))
                            )
                    )
                }
            }
        }

        func glucoseStats()
            -> (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
        {
            // First date
            let previous = glucose.last?.date ?? Date()
            // Last date (recent)
            let current = glucose.first?.date ?? Date()
            // Total time in days
            let numberOfDays = (current - previous).timeInterval / 8.64E4

            let denominator = numberOfDays < 1 ? 1 : numberOfDays

            let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
            let sumReadings = justGlucoseArray.reduce(0, +)
            let countReadings = justGlucoseArray.count

            let glucoseAverage = Double(sumReadings) / Double(countReadings)
            let medianGlucose = BareStatisticsView.medianCalculation(array: justGlucoseArray)

            var NGSPa1CStatisticValue = 0.0
            var IFCCa1CStatisticValue = 0.0

            if numberOfDays > 0 {
                NGSPa1CStatisticValue = (glucoseAverage + 46.7) / 28.7
                IFCCa1CStatisticValue = 10.929 * (NGSPa1CStatisticValue - 2.152)
            }

            var sumOfSquares = 0.0
            for array in justGlucoseArray {
                sumOfSquares += pow(Double(array) - Double(glucoseAverage), 2)
            }

            var sd = 0.0
            var cv = 0.0

            if glucoseAverage > 0 {
                sd = sqrt(sumOfSquares / Double(countReadings))
                cv = sd / Double(glucoseAverage) * 100
            }

            return (
                ifcc: IFCCa1CStatisticValue,
                ngsp: NGSPa1CStatisticValue,
                average: glucoseAverage * (units == .mmolL ? 0.0555 : 1),
                median: medianGlucose * (units == .mmolL ? 0.0555 : 1),
                sd: sd * (units == .mmolL ? 0.0555 : 1),
                cv: cv,
                readings: Double(countReadings) / denominator
            )
        }
    }

    struct LoopsView: View {
        let highLimit: Decimal
        let lowLimit: Decimal
        let units: GlucoseUnits
        let eA1cDisplayUnit: EstimatedA1cDisplayUnit
        let loopStatRecords: [LoopStatRecord]

        var body: some View {
            loops
        }

        private var loops: some View {
            let loops = loopStatRecords
            // First date
            let previous = loops.last?.end ?? Date()
            // Last date (recent)
            let current = loops.first?.start ?? Date()
            // Total time in days
            let totalTime = (current - previous).timeInterval / 8.64E4

            let durationArray = loops.compactMap({ each in each.duration })
            let durationArrayCount = durationArray.count
            // var durationAverage = durationArray.reduce(0, +) / Double(durationArrayCount)
            let medianDuration = medianCalculationDouble(array: durationArray)
            let successsNR = loops.compactMap({ each in each.loopStatus }).filter({ each in each!.contains("Success") }).count
            let errorNR = durationArrayCount - successsNR
            let total = Double(successsNR + errorNR) == 0 ? 1 : Double(successsNR + errorNR)
            let successRate: Double? = (Double(successsNR) / total) * 100
            let loopNr = totalTime <= 1 ? total : round(total / (totalTime != 0 ? totalTime : 1))
            let intervalArray = loops.compactMap({ each in each.interval as Double })
            let count = intervalArray.count != 0 ? intervalArray.count : 1
            let intervalAverage = intervalArray.reduce(0, +) / Double(count)
            // let maximumInterval = intervalArray.max()
            // let minimumInterval = intervalArray.min()
            return VStack(spacing: 10) {
                HStack(spacing: 35) {
                    VStack(spacing: 5) {
                        Text("Loops").font(.subheadline).foregroundColor(.primary)
                        Text(loopNr.formatted())
                    }
                    VStack(spacing: 5) {
                        Text("Interval").font(.subheadline).foregroundColor(.primary)
                        Text(intervalAverage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "m")
                    }
                    VStack(spacing: 5) {
                        Text("Duration").font(.subheadline).foregroundColor(.primary)
                        Text(
                            (medianDuration / 1000)
                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "s"
                        )
                    }
                    VStack(spacing: 5) {
                        Text("Success").font(.subheadline).foregroundColor(.primary)
                        Text(
                            ((successRate ?? 100) / 100)
                                .formatted(.percent.grouping(.never).rounded().precision(.fractionLength(1)))
                        )
                    }
                }
            }
        }

        private func medianCalculationDouble(array: [Double]) -> Double {
            BareStatisticsView.medianCalculationDouble(array: array)
        }
    }
}

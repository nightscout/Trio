import Foundation

/// https://doi.org/10.1177/19322968221085273
enum GRICalculator {
    struct Result: Equatable {
        let veryLowPercentage: Double
        let lowPercentage: Double
        let highPercentage: Double
        let veryHighPercentage: Double

        var hypoComponent: Double { veryLowPercentage + 0.8 * lowPercentage }
        var hyperComponent: Double { veryHighPercentage + 0.5 * highPercentage }
        var score: Double { min(100, uncappedScore) }

        var weightedHypoComponent: Double { 3 * hypoComponent }
        var weightedHyperComponent: Double { 1.6 * hyperComponent }
        var uncappedScore: Double { weightedHypoComponent + weightedHyperComponent }

        var zone: String {
            switch score {
            case ...20: return "A"
            case ...40: return "B"
            case ...60: return "C"
            case ...80: return "D"
            default: return "E"
            }
        }
    }

    static func calculate(glucoseValues: [Int]) -> Result? {
        var count = 0
        var veryLow = 0
        var low = 0
        var high = 0
        var veryHigh = 0
        for value in glucoseValues where value > 0 {
            count += 1
            switch value {
            case ..<54: veryLow += 1
            case ..<70: low += 1
            case 251...: veryHigh += 1
            case 181...: high += 1
            default: break
            }
        }
        guard count > 0 else { return nil }
        let percent = 100.0 / Double(count)
        return Result(
            veryLowPercentage: Double(veryLow) * percent,
            lowPercentage: Double(low) * percent,
            highPercentage: Double(high) * percent,
            veryHighPercentage: Double(veryHigh) * percent
        )
    }
}

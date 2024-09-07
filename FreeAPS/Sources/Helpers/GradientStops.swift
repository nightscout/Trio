import Foundation
import SwiftUI

struct GradientStops {
    static func calculateGradientStops(
        lowGlucose: Decimal,
        highGlucose: Decimal,
        glucoseValues: [Decimal]
    ) async -> [Gradient.Stop] {
        let low = Double(lowGlucose)
        let high = Double(highGlucose)

        let minimum = glucoseValues.min() ?? 0.0
        let maximum = glucoseValues.max() ?? 0.0

        // Handle edge case where minimum and maximum are equal
        guard minimum != maximum else {
            return [
                Gradient.Stop(color: .green, location: 0.0),
                Gradient.Stop(color: .green, location: 1.0)
            ]
        }

        // Calculate positions for gradient
        let lowPosition = (low - Double(truncating: minimum as NSNumber)) /
            (Double(truncating: maximum as NSNumber) - Double(truncating: minimum as NSNumber))
        let highPosition = (high - Double(truncating: minimum as NSNumber)) /
            (Double(truncating: maximum as NSNumber) - Double(truncating: minimum as NSNumber))

        // Ensure positions are in bounds [0, 1]
        let clampedLowPosition = max(0.0, min(lowPosition, 1.0))
        let clampedHighPosition = max(0.0, min(highPosition, 1.0))

        // Ensure lowPosition is less than highPosition
        let epsilon: CGFloat = 0.0001
        let sortedPositions = [clampedLowPosition, clampedHighPosition].sorted()
        var adjustedHighPosition = sortedPositions[1]

        if adjustedHighPosition - sortedPositions[0] < epsilon {
            adjustedHighPosition = min(1.0, sortedPositions[0] + epsilon)
        }

        return [
            Gradient.Stop(color: .red, location: 0.0),
            Gradient.Stop(color: .red, location: sortedPositions[0]), // draw red gradient till lowGlucose
            Gradient.Stop(color: .green, location: sortedPositions[0] + epsilon),
            // draw green above lowGlucose till highGlucose
            Gradient.Stop(color: .green, location: adjustedHighPosition),
            Gradient.Stop(color: .orange, location: adjustedHighPosition + epsilon), // draw orange above highGlucose
            Gradient.Stop(color: .orange, location: 1.0)
        ]
    }
}

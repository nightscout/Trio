import Foundation
import SwiftUI

// Helper function to decide how to pick the glucose color
public func getDynamicGlucoseColor(
    glucoseValue: Decimal,
    highGlucoseColorValue: Decimal,
    lowGlucoseColorValue: Decimal,
    targetGlucose: Decimal,
    glucoseColorScheme: GlucoseColorScheme
) -> Color {
    // Only use calculateHueBasedGlucoseColor if the setting is enabled in preferences
    if glucoseColorScheme == .dynamicColor {
        return calculateHueBasedGlucoseColor(
            glucoseValue: glucoseValue,
            highGlucose: highGlucoseColorValue,
            lowGlucose: lowGlucoseColorValue,
            targetGlucose: targetGlucose
        )
    }
    // Otheriwse, use static (orange = high, red = low, green = range)
    else {
        if glucoseValue >= highGlucoseColorValue {
            return Color.orange
        } else if glucoseValue <= lowGlucoseColorValue {
            return Color.red
        } else {
            return Color.green
        }
    }
}

// Dynamic color - Define the hue values for the key points
// We'll shift color gradually one glucose point at a time
// We'll shift through the rainbow colors of ROY-G-BIV from low to high
// Start at red for lowGlucose, green for targetGlucose, and violet for highGlucose
public func calculateHueBasedGlucoseColor(
    glucoseValue: Decimal,
    highGlucose: Decimal,
    lowGlucose: Decimal,
    targetGlucose: Decimal
) -> Color {
    let redHue: CGFloat = 0.0 / 360.0 // 0 degrees
    let greenHue: CGFloat = 120.0 / 360.0 // 120 degrees
    let purpleHue: CGFloat = 270.0 / 360.0 // 270 degrees

    // Calculate the hue based on the bgLevel
    var hue: CGFloat
    if glucoseValue <= lowGlucose {
        hue = redHue
    } else if glucoseValue >= highGlucose {
        hue = purpleHue
    } else if glucoseValue <= targetGlucose {
        // Interpolate between red and green
        let ratio = CGFloat(truncating: (glucoseValue - lowGlucose) / (targetGlucose - lowGlucose) as NSNumber)

        hue = redHue + ratio * (greenHue - redHue)
    } else {
        // Interpolate between green and purple
        let ratio = CGFloat(truncating: (glucoseValue - targetGlucose) / (highGlucose - targetGlucose) as NSNumber)
        hue = greenHue + ratio * (purpleHue - greenHue)
    }
    // Return the color with full saturation and brightness
    let color = Color(hue: hue, saturation: 0.6, brightness: 0.9)
    return color
}

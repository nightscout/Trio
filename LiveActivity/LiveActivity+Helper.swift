//
//  LiveActivity+Helper.swift
//  LiveActivityExtension
//
//  Created by Cengiz Deniz on 17.10.24.
//
import ActivityKit
import Charts
import SwiftUI
import WidgetKit

enum Size {
    case minimal
    case compact
    case expanded
}

enum GlucoseUnits: String, Equatable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    static let exchangeRate: Decimal = 0.0555
}

enum GlucoseColorScheme: String, Equatable {
    case staticColor
    case dynamicColor
}

func rounded(_ value: Decimal, scale: Int, roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
    var result = Decimal()
    var toRound = value
    NSDecimalRound(&result, &toRound, scale, roundingMode)
    return result
}

extension Int {
    var asMmolL: Decimal {
        rounded(Decimal(self) * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var formattedAsMmolL: String {
        NumberFormatter.glucoseFormatter.string(from: asMmolL as NSDecimalNumber) ?? "\(asMmolL)"
    }
}

extension Decimal {
    var asMmolL: Decimal {
        rounded(self * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var asMgdL: Decimal {
        rounded(self / GlucoseUnits.exchangeRate, scale: 0, roundingMode: .plain)
    }

    var formattedAsMmolL: String {
        NumberFormatter.glucoseFormatter.string(from: asMmolL as NSDecimalNumber) ?? "\(asMmolL)"
    }
}

extension NumberFormatter {
    static let glucoseFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

extension Color {
    // Helper function to decide how to pick the glucose color
    static func getDynamicGlucoseColor(
        glucoseValue: Decimal,
        highGlucoseColorValue: Decimal,
        lowGlucoseColorValue: Decimal,
        targetGlucose: Decimal,
        glucoseColorScheme: String
    ) -> Color {
        // Only use calculateHueBasedGlucoseColor if the setting is enabled in preferences
        if glucoseColorScheme == "dynamicColor" {
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
    private static func calculateHueBasedGlucoseColor(
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
}

func bgAndTrend(
    context: ActivityViewContext<LiveActivityAttributes>,
    size: Size,
    glucoseColor: Color
) -> (some View, Int) {
    let hasStaticColorScheme = context.state.glucoseColorScheme == "staticColor"

    var characters = 0

    let bgText = context.state.bg
    characters += bgText.count

    // narrow mode is for the minimal dynamic island view
    // there is not enough space to show all three arrow there
    // and everything has to be squeezed together to some degree
    // only display the first arrow character and make it red in case there were more characters
    var directionText: String?
    if let direction = context.state.direction {
        if size == .compact || size == .minimal {
            directionText = String(direction[direction.startIndex ... direction.startIndex])
        } else {
            directionText = direction
        }

        characters += directionText!.count
    }

    let spacing: CGFloat
    switch size {
    case .minimal: spacing = -1
    case .compact: spacing = 0
    case .expanded: spacing = 3
    }

    let stack = HStack(spacing: spacing) {
        Text(bgText)
            .foregroundStyle(hasStaticColorScheme ? .primary : glucoseColor)
            .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
        if let direction = directionText {
            let text = Text(direction)
            switch size {
            case .minimal:
                let scaledText = text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading)
                scaledText.foregroundStyle(hasStaticColorScheme ? .primary : glucoseColor)
            case .compact:
                text.scaleEffect(x: 0.8, y: 0.8, anchor: .leading).padding(.trailing, -3)

            case .expanded:
                text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading).padding(.trailing, -5)
            }
        }
    }.foregroundStyle(hasStaticColorScheme ? .primary : glucoseColor)
        .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))

    return (stack, characters)
}

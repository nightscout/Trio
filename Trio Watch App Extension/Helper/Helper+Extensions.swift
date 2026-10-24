import Foundation
import SwiftUI

extension Binding where Value == Int {
    func doubleBinding() -> Binding<Double> {
        Binding<Double>(
            get: { Double(self.wrappedValue) },
            set: { self.wrappedValue = Int($0) }
        )
    }
}

extension Color {
    static let bgDarkBlue = Color("Background_DarkBlue")
    static let bgDarkerDarkBlue = Color("Background_DarkerDarkBlue")
}

extension String {
    func toColor() -> Color {
        var hexString = trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        return Color(red: red, green: green, blue: blue)
    }
}

/// The phone's glucose colors for the watch's readings: its `getDynamicGlucoseColor` with the range, target and color
/// scheme it sends, as the Live Activity has it. Needs to be kept in sync with DynamicGlucoseColor.swift.
struct WatchGlucoseColoring {
    /// mg/dL
    var low: Decimal = 70
    var high: Decimal = 180
    var target: Decimal = 100
    var isDynamic = false

    init() {}

    init(_ payload: [String: Any]) {
        if let low = payload[WatchMessageKeys.glucoseRangeLow] as? Double { self.low = Decimal(low) }
        if let high = payload[WatchMessageKeys.glucoseRangeHigh] as? Double { self.high = Decimal(high) }
        if let target = payload[WatchMessageKeys.glucoseRangeTarget] as? Double { self.target = Decimal(target) }
        isDynamic = payload[WatchMessageKeys.glucoseColorScheme] as? String == "dynamicColor"
    }

    func color(_ glucose: Decimal) -> Color {
        // the dynamic scheme ramps between fixed ends, as on the phone
        let lowColorValue: Decimal = isDynamic ? 55 : low
        let highColorValue: Decimal = isDynamic ? 220 : high
        guard isDynamic else {
            if glucose >= highColorValue { return Self.staticHigh }
            if glucose <= lowColorValue { return Self.staticLow }
            return Self.staticInRange
        }

        // red at the low end, green at the target, violet at the high end
        let redHue: CGFloat = 0.0 / 360.0
        let greenHue: CGFloat = 120.0 / 360.0
        let purpleHue: CGFloat = 270.0 / 360.0
        let hue: CGFloat
        if glucose <= lowColorValue {
            hue = redHue
        } else if glucose >= highColorValue {
            hue = purpleHue
        } else if glucose <= target {
            let ratio = CGFloat(truncating: (glucose - lowColorValue) / (target - lowColorValue) as NSNumber)
            hue = redHue + ratio * (greenHue - redHue)
        } else {
            let ratio = CGFloat(truncating: (glucose - target) / (highColorValue - target) as NSNumber)
            hue = greenHue + ratio * (purpleHue - greenHue)
        }
        return Color(hue: hue, saturation: 0.6, brightness: 0.9)
    }

    private static let staticLow = Color(hue: 0.0 / 360.0, saturation: 0.6, brightness: 0.9)
    private static let staticInRange = Color(hue: 120.0 / 360.0, saturation: 0.6, brightness: 0.9)
    private static let staticHigh = Color(hue: 270.0 / 360.0, saturation: 0.6, brightness: 0.9)
}

import SwiftUI

extension UIColor {
    // MARK: - HIG colors

    // See: https://developer.apple.com/ios/human-interface-guidelines/visual-design/color/

    // HIG Green has changed for iOS 13. This is the legacy color.
    static func HIGGreenColor() -> UIColor {
        UIColor(red: 76 / 255, green: 217 / 255, blue: 100 / 255, alpha: 1)
    }
}

// MARK: - Color palette for common elements

extension UIColor {
    @nonobjc static let carbs = UIColor(named: "carbs") ?? systemGreen

    @nonobjc static let fresh = UIColor(named: "fresh") ?? HIGGreenColor()

    @nonobjc static let glucose = UIColor(named: "glucose") ?? systemTeal

    @nonobjc static let insulin = UIColor(named: "insulin") ?? systemOrange

    // The loopAccent color is intended to be use as the app accent color.
    @nonobjc public static let loopAccent = UIColor(named: "accent") ?? systemBlue

    @nonobjc public static let warning = UIColor(named: "warning") ?? systemYellow
}

// MARK: - Context for colors

public extension UIColor {
    @nonobjc static let agingColor = warning

    @nonobjc static let axisLabelColor = secondaryLabel

    @nonobjc static let axisLineColor = clear

    @nonobjc static let cellBackgroundColor = secondarySystemBackground

    @nonobjc static let carbTintColor = carbs

    @nonobjc internal static let critical = systemRed

    @nonobjc static let destructive = critical

    @nonobjc static let freshColor = fresh

    @nonobjc static let glucoseTintColor = glucose

    @nonobjc static let gridColor = systemGray3

    @nonobjc static let invalid = critical

    @nonobjc static let insulinTintColor = insulin

    @nonobjc static let pumpStatusNormal = insulin

    @nonobjc static let staleColor = critical

    @nonobjc static let unknownColor = systemGray4
}

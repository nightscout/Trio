import SwiftUI
import UIKit

extension Color {
    static let carbs = Color("carbs")

    static let fresh = Color("fresh")

    static let glucose = Color("glucose")

    static let insulin =
        // workaround for 'No color named 'Insulin' found in asset catalog' error which is most likely a bug
        Color(
            UIColor(named: "Insulin") ??
                UIColor(red: 0.118, green: 0.588, blue: 0.988, alpha: 1.0) // these are RGB of our insulin color
        )

    // The loopAccent color is intended to be use as the app accent color.
    public static let loopAccent = Color("accent")

    public static let warning = Color("warning")
}

// Color version of the UIColor context colors
public extension Color {
    static let agingColor = warning

    static let axisLabelColor = secondary

    static let axisLineColor = clear

    #if os(iOS)
        static let cellBackgroundColor = Color(UIColor.cellBackgroundColor)
        static let gridColor = Color(UIColor.gridColor)
        static let unknownColor = Color(UIColor.unknownColor)
    #endif

    static let carbTintColor = carbs

    static let critical = red

    static let destructive = critical

    static let glucoseTintColor = glucose

    static let invalid = critical

    static let insulinTintColor = insulin

    static let pumpStatusNormal = insulin

    static let staleColor = critical
}

extension Color {
    static let loopGray = Color("LoopGray")
    static let loopGreen = Color("LoopGreen")
    static let loopYellow = Color("LoopYellow")
    static let loopRed = Color("LoopRed")
    static let loopManualTemp = Color("ManualTempBasal")
    static let bgDarkBlue = Color("Background_DarkBlue")
    static let bgDarkerDarkBlue = Color("Background_DarkerDarkBlue")
    static let chart = Color("Chart")
    static let tabBar = Color("TabBar")
    //   static let insulin = Color("Insulin")
    static let uam = Color("UAM")
    static let zt = Color("ZT")
    static let tempBasal = Color("TempBasal")
    static let basal = Color("Basal")
    static let darkerBlue = Color("DarkerBlue")
    static let loopPink = Color("LoopPink")
    static let lemon = Color("Lemon")
    static let minus = Color("minus")
    static let darkGray = Color("darkGray")
}

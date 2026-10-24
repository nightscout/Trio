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

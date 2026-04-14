import CoreGraphics
import Foundation

extension Double {
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSNumber)
    }

    func roundedDouble(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension Int {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

extension Int16 {
    var minutes: TimeInterval {
        TimeInterval(self) * 60
    }
}

extension CGFloat {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

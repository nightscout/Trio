import CoreGraphics
import Foundation

extension Double {
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSNumber)
    }
}

extension Int {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

extension CGFloat {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

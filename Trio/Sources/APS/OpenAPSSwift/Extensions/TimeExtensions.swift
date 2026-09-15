import Foundation

extension Int {
    var minutesToSeconds: TimeInterval {
        Double(self * 60)
    }

    var hoursToSeconds: TimeInterval {
        Double(minutesToSeconds * 60)
    }
}

extension Decimal {
    var minutesToSeconds: TimeInterval {
        Double(self * 60)
    }

    var hoursToSeconds: TimeInterval {
        Double(minutesToSeconds * 60)
    }
}

extension TimeInterval {
    var secondsToMinutes: Decimal {
        Decimal(self / 60)
    }
}

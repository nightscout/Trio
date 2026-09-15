extension Double {
    /// Approximate matching to check if it is within +/- epsilon
    func isApproximatelyEqual(to other: Double, epsilon: Double?) -> Bool {
        // If no epsilon provided, require exact match
        guard let epsilon = epsilon else {
            return self == other
        }

        // Handle exact equality
        if self == other {
            return true
        }

        // Handle infinity and NaN
        if isInfinite || other.isInfinite || isNaN || other.isNaN {
            return self == other
        }

        // For IOB values, use simple absolute difference
        return abs(self - other) <= epsilon
    }

    /// Applies a simple clamp to Doubles
    func clamp(lowerBound: Double, upperBound: Double) -> Double {
        if self < lowerBound {
            return lowerBound
        } else if self > upperBound {
            return upperBound
        } else {
            return self
        }
    }
}

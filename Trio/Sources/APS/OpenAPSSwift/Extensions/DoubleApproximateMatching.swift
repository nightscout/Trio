extension Double {
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
}

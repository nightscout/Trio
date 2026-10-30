import Foundation

/// AAPS exponential glucose smoothing, kept apart from storage so every device that loops feeds the
/// algorithm the same values.
enum GlucoseSmoothing {
    /// Readings the phone smooths over: the last day, at most this many.
    static let maximumReadings = 350

    /// The smoothed values for `readings` (oldest first, CGM only, raw mg/dL). nil leaves a reading's
    /// stored smoothed value as it was.
    static func smoothed(
        _ readings: [(date: Date?, glucose: Int)],
        minimumWindowSize: Int = 4,
        maximumAllowedGapMinutes: Int = 12,
        xDripErrorGlucose: Int = 38,
        minimumSmoothedGlucose: Decimal = 39,
        firstOrderWeight: Decimal = 0.4,
        firstOrderAlpha: Decimal = 0.5,
        secondOrderAlpha: Decimal = 0.4,
        secondOrderBeta: Decimal = 1.0
    ) -> [Decimal?] {
        var result = [Decimal?](repeating: nil, count: readings.count)
        guard !readings.isEmpty else { return result }

        // Size of the valid most-recent window: walk adjacent pairs from newest to oldest.
        var validWindowCount = max(readings.count - 1, 0)
        for (recentOffset, pair) in zip(readings.dropFirst().reversed(), readings.dropLast().reversed()).enumerated() {
            let (newer, older) = pair
            guard let newerDate = newer.date, let olderDate = older.date else { continue }

            let gapMinutesRounded = Int((newerDate.timeIntervalSince(olderDate) / 60.0).rounded())
            if gapMinutesRounded >= maximumAllowedGapMinutes {
                validWindowCount = recentOffset + 1 // include the more recent reading
                break
            }
            // Ported from AAPS: 38 mg/dL may represent an xDrip error state.
            if newer.glucose == xDripErrorGlucose {
                validWindowCount = recentOffset // exclude this 38 value
                break
            }
        }

        let windowStart = readings.count - validWindowCount

        // Not enough recent contiguous readings to smooth: only the recent window falls back to raw.
        guard validWindowCount >= minimumWindowSize else {
            for index in windowStart ..< readings.count {
                result[index] = max(Decimal(readings[index].glucose), minimumSmoothedGlucose)
            }
            return result
        }

        let window = Array(readings[windowStart...])
        guard window.count >= 2 else { return result }

        // 1st order
        var firstOrder: [Decimal] = []
        var firstOrderCurrent = Decimal(window[0].glucose)
        firstOrder.append(firstOrderCurrent)
        for sample in window.dropFirst() {
            firstOrderCurrent = firstOrderCurrent + firstOrderAlpha * (Decimal(sample.glucose) - firstOrderCurrent)
            firstOrder.append(firstOrderCurrent)
        }

        // 2nd order
        var secondOrder: [Decimal] = []
        var previousSmoothed = Decimal(window[0].glucose)
        var previousDelta = Decimal(window[1].glucose - window[0].glucose)
        secondOrder.append(previousSmoothed)
        for sample in window.dropFirst() {
            let next = secondOrderAlpha * Decimal(sample.glucose)
                + (1 - secondOrderAlpha) * (previousSmoothed + previousDelta)
            let nextDelta = secondOrderBeta * (next - previousSmoothed) + (1 - secondOrderBeta) * previousDelta
            previousSmoothed = next
            previousDelta = nextDelta
            secondOrder.append(next)
        }

        for (offset, (first, second)) in zip(firstOrder, secondOrder).enumerated() {
            let blended = firstOrderWeight * first + (1 - firstOrderWeight) * second
            // nearest integer, ties away from zero
            result[windowStart + offset] = max(blended.rounded(toPlaces: 0), minimumSmoothedGlucose)
        }
        return result
    }
}

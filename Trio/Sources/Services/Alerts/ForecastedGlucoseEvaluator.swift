import Foundation

/// Picks a predicted-glucose value at a fixed horizon across the available
/// `Determination.predictions` curves (IOB / COB / UAM / ZT).
///
/// Mirrors the multi-curve selection in the oref-swift port
/// (`ForecastGenerator.blendForecasts`) but at a single index instead of
/// across the post-peak window. The Trio determination JSON already holds
/// every curve at 5-min increments, so index 4 ≈ +20 min.
///
/// Reduction is `min` of available curves at the horizon — conservative for
/// low detection. oref-swift's own blender uses `max` because it feeds SMB
/// dosing safety; flipping to `min` for an alarm uses the same input set but
/// with the inverted intent.
enum ForecastedGlucoseEvaluator {
    static let defaultHorizonMinutes = 20

    enum Curve: String { case iob, cob, uam, zt }

    struct Result: Equatable {
        let predictedGlucose: Decimal
        let horizonMinutes: Int
        let curvesUsed: Set<Curve>
        let perCurve: [Curve: Decimal]
    }

    static func evaluate(
        determination: Determination,
        horizonMinutes: Int = defaultHorizonMinutes
    ) -> Result? {
        let index = horizonMinutes / 5
        guard let predictions = determination.predictions else { return nil }

        var samples: [Curve: Decimal] = [:]
        if let v = sample(predictions.iob, at: index) { samples[.iob] = v }
        if let v = sample(predictions.cob, at: index) { samples[.cob] = v }
        if let v = sample(predictions.uam, at: index) { samples[.uam] = v }
        if let v = sample(predictions.zt, at: index) { samples[.zt] = v }
        guard let minSample = samples.values.min() else { return nil }

        return Result(
            predictedGlucose: minSample,
            horizonMinutes: horizonMinutes,
            curvesUsed: Set(samples.keys),
            perCurve: samples
        )
    }

    private static func sample(_ array: [Int]?, at index: Int) -> Decimal? {
        guard let array, array.indices.contains(index) else { return nil }
        return Decimal(array[index])
    }
}

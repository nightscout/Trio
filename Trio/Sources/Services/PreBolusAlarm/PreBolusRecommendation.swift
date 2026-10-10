import Foundation
import LoopKit

/// A recommended pre-bolus lead time (how long to wait between delivering the bolus and the first
/// bite of the meal), together with a short explanation of why.
///
/// Bases follow the clinical consensus that first-generation rapid-acting analogues (aspart, lispro,
/// glulisine) are best given 15–20 min before food; the ultra-rapid formulations (Fiasp, Lyumjev)
/// onset roughly twice as fast and earn ~5 min less.
struct PreBolusRecommendation: Equatable {
    /// Suggested lead time in minutes, clamped to `0...``Config/maxMinutes``.
    let minutes: Int

    /// Lead time implied by the meal's composition alone, before insulin onset and glucose.
    let mealBase: Int

    /// Minutes the insulin's onset speed took off ``mealBase``. Zero for rapid-acting insulins,
    /// negative for ultra-rapid ones.
    let insulinAdjustment: Int

    /// ``mealBase`` after the insulin adjustment: what the meal contributes before glucose.
    let baseMinutes: Int

    /// Minutes that glucose level and trend added to ``baseMinutes``. Never negative: glucose below
    /// target or falling is handled by the safety gate instead.
    let adjustment: Int

    /// Why the meal landed on ``mealBase``. Empty when a safety rule fired.
    let baseReason: String

    /// Why the insulin changed the lead time. `nil` when it did not.
    let insulinAdjustmentReason: String?

    /// Why glucose changed the lead time. `nil` when a safety rule fired.
    let adjustmentReason: String?

    /// Set when a safety rule forced the answer to zero and suppressed the rest of the breakdown.
    let gateReason: String?

    /// Whether glucose is low enough that the user should treat the low instead of pre-bolusing.
    let isBelowLowThreshold: Bool

    /// A safety rule short-circuited the calculation.
    var isGated: Bool { gateReason != nil }

    /// The full explanation as one sentence run, used where there is no room for the breakdown.
    var reason: String {
        if let gateReason { return gateReason }
        return [baseReason, insulinAdjustmentReason, adjustmentReason].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The result before the cap. Differs from ``minutes`` only for a meal well above target or
    /// rising on a fast-carb base.
    var uncappedMinutes: Int { baseMinutes + adjustment }

    static let none = PreBolusRecommendation(
        minutes: 0,
        mealBase: 0,
        insulinAdjustment: 0,
        baseMinutes: 0,
        adjustment: 0,
        baseReason: "",
        insulinAdjustmentReason: nil,
        adjustmentReason: nil,
        gateReason: nil,
        isBelowLowThreshold: false
    )

    /// Hard-coded thresholds, all in mg/dL, grams or minutes.
    enum Config {
        /// Below this, don't pre-bolus at all: treat the low first. Matches level-1 hypoglycaemia.
        static let lowThreshold: Decimal = 70

        /// Used only when no target is available from the profile or the latest determination.
        static let defaultTarget: Decimal = 110

        /// Half-width of the "at target" window.
        static let atTargetBand: Decimal = 10

        /// How far above target counts as "well above", earning the larger adjustment.
        static let wellAboveBand: Decimal = 54

        /// Glucose delta (over the ~20 min window the state model tracks) that counts as falling.
        ///
        /// −15 over 20 min is 0.75 mg/dL/min, just inside the band every CGM still draws as a flat
        /// arrow (Dexcom/Libre: |rate| < 1 mg/dL/min) and just before ↘ would appear
        /// (1–2 mg/dL/min). It is a fallback for when no arrow is available, so it should fire a
        /// little earlier than the arrow would, but not on sensor noise: the previous −5
        /// (0.25 mg/dL/min) gated most steady at-target meals.
        static let fallingDelta: Decimal = -15

        /// Glucose delta over the same window that counts as rising when no arrow is available.
        /// Mirror of ``fallingDelta``.
        static let risingDelta: Decimal = 15

        /// Carbs explicitly logged with no fat or protein at all are treated as fast-acting.
        static let fastCarbFloor: Decimal = 30

        /// Base lead for a standard or mixed meal, before the insulin adjustment.
        static let standardMealBase = 15

        /// Base lead for a meal of fast carbs only, before the insulin adjustment.
        static let fastCarbMealBase = 20

        /// Extra lead for glucose rising into the meal: by the time the insulin peaks the start
        /// point will already be higher than the current reading.
        static let risingAdjustment = 5

        /// Ceiling on the suggestion. Slightly conservative relative to the common 30-min top end
        /// for very high glucose; kept at 25 so a delayed meal does not run into the insulin peak.
        static let maxMinutes = 25
    }

    /// How an insulin's onset speed shifts the meal base.
    ///
    /// Fiasp and Lyumjev are both ultra-rapid formulations: PK studies put Fiasp's onset at roughly
    /// twice that of NovoRapid (≈4 vs 9 min) with double the exposure in the first 30 min, and
    /// Lyumjev shows the same shift over Humalog (absorbing marginally faster than Fiasp still).
    /// That is a few minutes gained, not a class gap between the two, so both share the same saving.
    enum InsulinLeadProfile {
        case novolog
        case humalog
        case apidra
        case fiasp
        case lyumjev

        /// Unknown insulin (and Afrezza, which Trio does not offer for pumps) assumes Novolog,
        /// the conservative default.
        init(_ insulinType: InsulinType?) {
            switch insulinType {
            case .humalog: self = .humalog
            case .apidra: self = .apidra
            case .fiasp: self = .fiasp
            case .lyumjev: self = .lyumjev
            default: self = .novolog
            }
        }

        /// Fiasp and Lyumjev onset roughly twice as fast as their parent analogues.
        var isUltraRapid: Bool {
            switch self {
            case .fiasp,
                 .lyumjev: return true
            case .apidra,
                 .humalog,
                 .novolog: return false
            }
        }

        /// Minutes ultra-rapid onset saves off any meal base.
        var ultraRapidSaving: Int { isUltraRapid ? 5 : 0 }
    }

    /// Glucose trends that count as falling regardless of the numeric delta.
    private static let fallingDirections: Set<BloodGlucose.Direction> = [
        .fortyFiveDown, .singleDown, .doubleDown, .tripleDown
    ]

    /// Glucose trends that count as rising regardless of the numeric delta.
    private static let risingDirections: Set<BloodGlucose.Direction> = [
        .fortyFiveUp, .singleUp, .doubleUp, .tripleUp
    ]

    /// Derives a pre-bolus lead time from the composition of the meal and from starting glucose
    /// relative to target.
    ///
    /// - Parameters:
    ///   - currentBG: Most recent glucose reading in mg/dL. Pass 0 when unknown.
    ///   - deltaBG: Change in glucose in mg/dL over the state model's ~20 minute window.
    ///   - target: Glucose target in mg/dL. Falls back to ``Config/defaultTarget`` when not positive.
    ///   - direction: Trend arrow from the most recent reading, if available.
    ///   - carbs: Carbohydrates in grams.
    ///   - fat: Fat in grams.
    ///   - protein: Protein in grams.
    ///   - insulinType: The insulin the pump delivers. Drives the base lead time via
    ///     ``InsulinLeadProfile``; `nil` assumes a rapid-acting insulin, the conservative default.
    ///   - fatAndProteinTracked: `true` when the user has fat/protein entry enabled, so
    ///     `fat == 0 && protein == 0` is a deliberate statement about the meal. Defaults to `false`:
    ///     an empty pair then means "not entered", and the standard base applies.
    ///   - isGlucoseFresh: Whether the latest reading is recent enough to act on. A stale reading
    ///     gates the suggestion to zero.
    static func evaluate(
        currentBG: Decimal,
        deltaBG: Decimal,
        target: Decimal,
        direction: BloodGlucose.Direction?,
        carbs: Decimal,
        fat: Decimal,
        protein: Decimal,
        insulinType: InsulinType? = nil,
        fatAndProteinTracked: Bool = false,
        isGlucoseFresh: Bool = true
    ) -> PreBolusRecommendation {
        let target = target > 0 ? target : Config.defaultTarget

        // Stage 1: safety gate. Any of these forces zero outright; insulin must not get a head
        // start on a glucose level that is already heading the wrong way.

        // Without a recent reading the low/falling checks below would run on old data, and the
        // delta falls back to 0, which reads as "steady".
        if !isGlucoseFresh {
            return gated(String(localized: "No recent glucose reading. Bolus with the first bite."))
        }

        // A glucose of 0 means "no reading yet" rather than a genuine low, so don't trip the
        // low-glucose branch on it.
        if currentBG > 0, currentBG < Config.lowThreshold {
            return gated(String(localized: "Treat the low first, no pre-bolus."), isBelowLowThreshold: true)
        }

        let isTrendingDown = direction.map { fallingDirections.contains($0) } ?? false
        if isTrendingDown || deltaBG <= Config.fallingDelta {
            return gated(String(localized: "Glucose is falling. Bolus with the first bite."))
        }

        if currentBG > 0, currentBG < target - Config.atTargetBand {
            return gated(String(localized: "Below target. Bolus with the first bite."))
        }

        // Stage 2: base lead time from how fast the carbs land, shifted by insulin onset speed.
        //
        // The standard base is the default. The fast-carb base only applies when fat/protein entry
        // is enabled and the user explicitly logged carbs with no fat or protein; without tracking,
        // an empty pair means "not entered", and treating it as fast carbs would over-lead ordinary
        // meals.
        //
        // Fat and protein deliberately do not shorten this: they are converted to delayed carb
        // equivalents covered later by the loop, so shortening the lead would count that delay twice
        // and under-lead the carbs actually being dosed for.
        let leadProfile = InsulinLeadProfile(insulinType)
        let mealBase: Int
        let baseReason: String

        if fatAndProteinTracked, fat == 0, protein == 0, carbs >= Config.fastCarbFloor {
            // Deliberately logged with no fat or protein at all: our proxy for a fast-acting carb
            // load (juice, cereal, fruit, white bread). Anything alongside slows gastric emptying
            // enough to drop back to the standard lead.
            mealBase = Config.fastCarbMealBase
            baseReason = String(localized: "Fast carbs land before the insulin does.")
        } else {
            mealBase = Config.standardMealBase
            if fat + protein > 0 {
                baseReason = String(localized: "Mixed meal. Fat and protein are dosed later, so this covers the carbs.")
            } else {
                baseReason = String(localized: "Normal meal.")
            }
        }

        let insulinAdjustment = -leadProfile.ultraRapidSaving
        let insulinAdjustmentReason: String? = leadProfile.isUltraRapid
            ? String(localized: "Ultra-rapid insulin onsets about twice as fast, so it needs less of a head start.")
            : nil
        let baseMinutes = mealBase + insulinAdjustment

        // Stage 3: adjust for where glucose sits and where it is heading. Only upward; everything
        // below target or falling was already caught by the gate.
        let levelAdjustment: Int
        let levelReason: String

        if currentBG > target + Config.wellAboveBand {
            levelAdjustment = 10
            levelReason = String(localized: "Well above target. Lead the meal further.")
        } else if currentBG > target + Config.atTargetBand {
            levelAdjustment = 5
            levelReason = String(localized: "Above target. Lead the meal a little further.")
        } else {
            levelAdjustment = 0
            levelReason = ""
        }

        // A rising trend means the effective starting point is higher than the current reading by
        // the time the insulin peaks (↗ alone is +30–60 mg/dL in 30 min), so lead a little more.
        // The arrow is authoritative; the numeric delta only stands in when no arrow is available.
        let isTrendingUp = direction.map { risingDirections.contains($0) } ?? (deltaBG >= Config.risingDelta)
        let trendAdjustment = isTrendingUp ? Config.risingAdjustment : 0

        let adjustment = levelAdjustment + trendAdjustment
        let adjustmentReason: String
        switch (levelAdjustment > 0, isTrendingUp) {
        case (true, true):
            adjustmentReason = levelReason + " " + String(localized: "Rising too, so add a little more.")
        case (true, false):
            adjustmentReason = levelReason
        case (false, true):
            adjustmentReason = String(localized: "At target but rising. Lead the meal a little further.")
        case (false, false):
            adjustmentReason = String(localized: "At target and steady, so no change.")
        }

        return PreBolusRecommendation(
            minutes: min(baseMinutes + adjustment, Config.maxMinutes),
            mealBase: mealBase,
            insulinAdjustment: insulinAdjustment,
            baseMinutes: baseMinutes,
            adjustment: adjustment,
            baseReason: baseReason,
            insulinAdjustmentReason: insulinAdjustmentReason,
            adjustmentReason: adjustmentReason,
            gateReason: nil,
            isBelowLowThreshold: false
        )
    }

    private static func gated(_ reason: String, isBelowLowThreshold: Bool = false) -> PreBolusRecommendation {
        PreBolusRecommendation(
            minutes: 0,
            mealBase: 0,
            insulinAdjustment: 0,
            baseMinutes: 0,
            adjustment: 0,
            baseReason: "",
            insulinAdjustmentReason: nil,
            adjustmentReason: nil,
            gateReason: reason,
            isBelowLowThreshold: isBelowLowThreshold
        )
    }
}

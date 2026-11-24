import Foundation

extension SettingsAnalysis {
    struct Engine {
        let units: GlucoseUnits
        var loadHistory: (TimeFrame, Set<String>) async -> History = {
            await HistoryLoader.load($0, excludedAdjustments: $1)
        }

        /// `excludedAdjustments` holds `Adjustment.id`s the user does not want counted as activity.
        func analyze(
            timeFrame: TimeFrame,
            excludedAdjustments: Set<String> = [],
            snapshot: SettingsSnapshot,
            catalog: Catalog?,
            catalogError: String?
        ) async -> Report {
            let history = await loadHistory(timeFrame, excludedAdjustments)
            return Self.report(
                history: history,
                timeFrame: timeFrame,
                snapshot: snapshot,
                catalog: catalog,
                catalogError: catalogError,
                units: units
            )
        }

        static func report(
            history: History,
            timeFrame: TimeFrame,
            snapshot: SettingsSnapshot,
            catalog: Catalog?,
            catalogError: String?,
            units: GlucoseUnits,
            now: Date = Date()
        ) -> Report {
            let detectors = Detectors(history: history, timeFrame: timeFrame, units: units)
            let days = max(timeFrame.days, 1.0 / 24)
            let guardEffect = PatternGuards.effect(for: snapshot)
            let mealProfile = detectors.mealProfile
            var findings: [Finding] = []
            var notDetected: [Scenario] = []
            var unavailable: [UnavailableScenario] = []

            for scenario in Scenario.allCases {
                // P12: carb-based scenarios need logged meals.
                var guardIDs = guardEffect.guardIDs
                var guardAdjustment = guardEffect.confidenceAdjustment
                if scenario.requiresCarbEntries {
                    switch mealProfile.style {
                    case .unannounced:
                        unavailable.append(UnavailableScenario(
                            scenario: scenario,
                            reason: String(
                                localized: "Needs logged carbs. \(mealProfile.loggedCount) meals were logged in this time frame. See Unannounced Meal Rise instead."
                            )
                        ))
                        continue
                    case .partial:
                        guardAdjustment -= 1
                        guardIDs.append("P12")
                    case .announced:
                        break
                    }
                }

                let detection = detectors.detect(scenario)
                let count = detection.occurrences.count
                guard count > 0 else {
                    notDetected.append(scenario)
                    continue
                }

                let perWeek = Double(count) / days * 7
                let severity: Severity = perWeek >= 4 ? .high : perWeek >= 1.5 ? .moderate : .low
                // Few events or a short time frame make a pattern less certain.
                let sampleAdjustment = count < 3 ? -1 : (days >= 28 && count >= 8 ? 1 : 0)
                let frameAdjustment = days < 3 ? -1 : 0
                let confidenceBoost = sampleAdjustment + frameAdjustment + guardAdjustment

                findings.append(
                    Finding(
                        scenario: scenario,
                        occurrences: detection.occurrences,
                        count: count,
                        perWeek: perWeek,
                        severity: severity,
                        pattern: detection.pattern,
                        advice: AdviceLibrary.advice(
                            for: scenario,
                            variant: detection.variant,
                            confidenceBoost: confidenceBoost
                        ),
                        guardIDs: guardIDs
                    )
                )
            }

            findings.sort {
                if $0.severity != $1.severity { return $0.severity > $1.severity }
                return $0.count > $1.count
            }

            let readings = detectors.glucose(in: timeFrame.start ... timeFrame.end)
            let inRange = readings.filter { (Detectors.Threshold.low ... Detectors.Threshold.high).contains($0.value) }.count

            return Report(
                timeFrame: timeFrame,
                checks: catalog.map { SettingsChecks.run(snapshot: snapshot, catalog: $0) },
                catalog: catalog,
                catalogError: catalogError,
                findings: findings,
                notDetected: notDetected,
                unavailable: unavailable,
                mealProfile: mealProfile,
                generatedAt: now,
                timeInRange: readings.isEmpty ? nil : Int((Double(inRange) / Double(readings.count) * 100).rounded()),
                readings: readings.count,
                expectedReadings: Int(timeFrame.duration / 300)
            )
        }
    }
}

// MARK: - Advice

/// Wording rule: advice names the setting a pattern *usually points to* and the
/// direction, never an amount ("reduce by 10%", "0.05 U/h"). How much to change
/// is left to the user and their care team.
private enum AdviceLibrary {
    typealias Advice = SettingsAnalysis.Advice
    typealias Confidence = SettingsAnalysis.Confidence

    static func advice(
        for scenario: SettingsAnalysis.Scenario,
        variant: SettingsAnalysis.AdviceVariant? = nil,
        confidenceBoost: Int
    ) -> Advice {
        let base: (target: String, recommendation: String, rationale: String, confidence: Confidence)

        switch (scenario, variant) {
        case (.bolusThenHypo, .prebolus?),
             (.bolusThenHypo, .unannounced?):
            base = (
                String(localized: "Prebolus size or SMB settings"),
                String(
                    localized: "This pattern usually indicates that too much insulin is given for meals that are not announced: a manual prebolus that is too large, or SMBs that keep going after the meal is covered."
                ),
                String(
                    localized: "When lows follow unannounced meals, the prebolus and the SMB and UAM limits matter more than the carb ratio. Look at this before raising any limits for meal highs."
                ),
                .medium
            )
        case (.unannouncedMeal, .prebolus?):
            base = (
                String(localized: "Prebolus, then SMB and UAM limits"),
                String(
                    localized: "This pattern usually indicates that the manual prebolus is too small or given too late for these meals, or that the SMB and UAM limits keep Trio from covering the rest of the rise."
                ),
                String(
                    localized: "If glucose rises before SMBs ramp up, the prebolus size or timing is the more likely cause. If SMBs stop while glucose keeps rising, look at Max SMB and UAM Basal Minutes and Max IOB."
                ),
                .medium
            )
        default:
            base = standardAdvice(for: scenario)
        }

        let confidenceValue = min(max(base.confidence.rawValue + confidenceBoost, 0), 2)
        return Advice(
            target: base.target,
            recommendation: base.recommendation,
            rationale: base.rationale,
            confidence: Confidence(rawValue: confidenceValue) ?? base.confidence
        )
    }

    private static func standardAdvice(
        for scenario: SettingsAnalysis.Scenario
    ) -> (target: String, recommendation: String, rationale: String, confidence: Confidence) {
        let base: (target: String, recommendation: String, rationale: String, confidence: Confidence)

        switch scenario {
        case .mealSpike:
            base = (
                String(localized: "Carb Ratio or meal timing"),
                String(
                    localized: "This pattern usually indicates that the carb ratio for this meal is too weak, or that the bolus is given too close to the meal."
                ),
                String(
                    localized: "If glucose comes back to target within a few hours, bolus timing is the more likely cause. If it stays high, the carb ratio for that time of day is worth reviewing."
                ),
                .medium
            )
        case .bolusThenHypo:
            base = (
                String(localized: "ISF or Carb Ratio"),
                String(
                    localized: "This pattern usually indicates that too much insulin is given for the situation: a too-strong ISF if the lows follow corrections, a too-strong carb ratio if they follow meals."
                ),
                String(
                    localized: "Whether carbs were still on board when the low happened helps tell the two apart."
                ),
                .medium
            )
        case .dawnPhenomenon:
            base = (
                String(localized: "Basal (early morning)"),
                String(
                    localized: "This pattern usually indicates that basal in the early morning is too low, starting some time before the rise."
                ),
                String(
                    localized: "A rise at the same clock time each day points to basal. A rise that follows getting up, whenever that is, usually does not."
                ),
                .high
            )
        case .overnightLow:
            base = (
                String(localized: "Basal (night)"),
                String(
                    localized: "This pattern usually indicates that basal during the night is too high, starting some time before the drop."
                ),
                String(
                    localized: "This only applies when there was no late bolus or treated low before the drop. Otherwise the evening insulin is the more likely cause."
                ),
                .medium
            )
        case .persistentHigh:
            base = (
                String(localized: "Infusion site, then ISF"),
                String(
                    localized: "This pattern often indicates an absorption problem with the infusion site. If the site is fine, it can point to an ISF that is too weak."
                ),
                String(
                    localized: "Highs that don't respond to insulin and cluster near the end of a site's life point to the site rather than your settings."
                ),
                .medium
            )
        case .delayedMealRise:
            base = (
                String(localized: "Fat & Protein"),
                String(
                    localized: "This pattern usually indicates that fat and protein from larger meals are not covered by the meal bolus."
                ),
                String(
                    localized: "A rise several hours after a meal is not explained by the carbs alone, so the carb ratio is usually not the setting to change."
                ),
                .low
            )
        case .exerciseDrop:
            base = (
                String(localized: "Temp target before activity"),
                String(
                    localized: "This pattern usually indicates that there is too much insulin on board when the activity starts."
                ),
                String(
                    localized: "Reducing insulin some time before the activity, for example with a temp target, usually helps more than changing your profile."
                ),
                .medium
            )
        case .unannouncedMeal:
            base = (
                String(localized: "SMB and UAM limits, or announcing meals"),
                String(
                    localized: "This pattern usually indicates that SMBs alone cannot keep up with these meals, either because the SMB and UAM limits are tight or because insulin only starts once glucose is already rising."
                ),
                String(
                    localized: "Insulin that starts with the rise arrives late for fast carbs. A small prebolus or announcing larger meals usually helps more than raising limits, especially if lows follow these meals."
                ),
                .low
            )
        }
        return base
    }
}

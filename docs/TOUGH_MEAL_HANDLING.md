# Tough Meal Handling — Feature Proposal

## The Problem: Prolonged Post-Meal Hyperglycemia from High-Carb, High-Fat/Protein Meals

### Case Study: Sushi Dinner — March 1, 2026

On the evening of February 28 / early morning March 1, a sushi meal exposed a significant limitation in the loop's ability to handle meals with prolonged, complex absorption profiles.

#### Meal Details

|Parameter            |Value                          |
|---------------------|-------------------------------|
|**Dose Timestamp**   |2026-03-01 01:49:58 UTC        |
|**Carbs Entered**    |80g                            |
|**Fat**              |20g                            |
|**Protein**          |50g                            |
|**BG at Dose**       |154 mg/dL (rising, FortyFiveUp)|
|**Recommended Dose** |5.65u                          |
|**User Dose**        |5.65u                          |
|**Super Bolus**      |Enabled                        |
|**Sensitivity Ratio**|1.08 (capped at 1.2 post-meal) |

#### Outcome

|Metric                     |Value                                    |
|---------------------------|-----------------------------------------|
|**Peak BG**                |307 mg/dL (at ~177 min / 3 hrs post-dose)|
|**BG at 2 hours**          |201 mg/dL                                |
|**BG at 4 hours**          |295 mg/dL                                |
|**BG at 8 hours**          |225 mg/dL                                |
|**Nadir BG**               |118 mg/dL (at 62 min)                    |
|**Time Above 180**         |395 minutes (6 hrs 35 min)               |
|**Time Below 70**          |0 minutes                                |
|**Total Insulin Delivered**|22.0u                                    |

#### Timeline of Events

The meal followed a characteristic pattern for rice-heavy meals with significant fat and protein:

1. **Minutes 0–60:** Initial bolus of 5.65u brought BG down from 154 to 118. Loop suspended basal, recognizing the active insulin.
1. **Minutes 60–140:** BG rebounded sharply from 118 → 267 as sushi rice absorption continued well beyond the modeled COB window. By minute 148, modeled COB hit 0, but glucose was clearly still being absorbed.
1. **Minutes 140–350:** BG plateaued in the 285–307 range. The loop attempted to correct with SMBs, but was constrained — `insulinReq` values frequently ranged from 1.0–3.2u, while actual SMB deliveries were capped at 0.5–0.6u per cycle. The loop was perpetually behind.
1. **Minutes 350–480:** BG began slowly declining from ~300 toward 225, driven by accumulated SMB insulin. Still significantly elevated 8 hours post-meal.

### The Core Issue

The loop's response was reactive rather than proactive. Three specific constraints prevented adequate insulin delivery:

1. **SMB size cap:** Maximum SMB delivery of ~0.5–0.6u per 5-minute cycle meant the loop could only deliver ~6u/hour via SMBs, even when it calculated a need for 2–3u immediately.
1. **Sensitivity ratio ceiling at 1.2:** The loop couldn't model the meal as requiring more aggressive dosing beyond this cap, limiting correction factor adjustments.
1. **Premature COB decay:** Modeled carbs-on-board reached 0 well before actual glucose absorption was complete, causing the loop to lose awareness that more glucose was incoming from the meal.

These constraints are appropriate safety measures for typical meals and non-meal scenarios, but they create a systematic inability to manage meals with prolonged, complex absorption — sushi, pizza, pasta with heavy sauces, large rice-based dishes, and similar meals.

-----

## Proposed Solutions

### Solution 1: "Tough Meal" Mode — Temporarily Raised SMB and IOB Limits

#### Description

The most direct lever available. Currently, the loop's SMBs are capped at ~0.5–0.6u, and maxIOB is set at 10u. During the sushi meal, the loop repeatedly calculated `insulinReq` of 1.0–3.2u but could only deliver a fraction of that per cycle. This creates a structural delay where the loop is always 30–60 minutes behind where it needs to be.

A "Tough Meal" mode would temporarily raise these limits for a configurable post-meal window:

- **maxSMB:** Raise from ~0.5–0.6u to 1.5–2.0u per cycle
- **maxIOB:** Raise from 10u to 12–14u
- **Duration:** 4–6 hours post-meal bolus, configurable
- **Activation:** User toggle at meal entry, or automatic (see Solution 5)

#### Expected Impact

This is likely the single highest-impact change. During the sushi meal's critical window (minutes 130–350), the loop averaged roughly one 0.5u SMB every 10 minutes. With a 1.5u cap, the same decisions would have delivered approximately 3x the correction insulin in the same timeframe. Back-of-envelope estimation suggests BG could have peaked closer to 240–250 rather than 307, and time above 180 could have been reduced from 395 minutes to approximately 200–250 minutes.

#### Practicality

High. This is a parameter change gated by a flag — no new algorithm development required. The loop's existing decision logic (`insulinReq` calculations, eventualBG predictions) already computes the needed insulin correctly; it's just limited in what it can deliver. Raising the cap lets the existing algorithm act on its own calculations more effectively.

#### Safety Concerns & Guardrails

- **Insulin stacking risk:** The primary danger is that higher SMBs could stack aggressively if the meal absorption profile is overestimated or if the user enters carbs incorrectly. If BG starts dropping faster than expected, higher IOB means a deeper potential low.
- **Guardrail — meal context only:** Only allow elevated limits when COB > 0, or within N hours of a confirmed meal bolus. Never in fasting state.
- **Guardrail — trend gating:** Only deliver elevated SMBs when BG is above a threshold (e.g., >150 mg/dL) AND trending up or flat. If BG starts dropping (FortyFiveDown or faster), immediately revert to normal SMB caps regardless of the timer.
- **Guardrail — progressive scaling:** Rather than a hard jump from 0.5u to 2.0u, scale the cap based on current BG. For example: cap = 0.5u when BG < 150, cap = 1.0u when BG 150–200, cap = 1.5u when BG 200–250, cap = 2.0u when BG > 250.
- **Guardrail — auto-expiry:** Mode automatically deactivates after the configured window, reverting to normal limits even if the user forgets.

-----

### Solution 2: Macro-Aware Extended Absorption Modeling

#### Description

The loop currently models carb absorption using a decay curve that brought COB to 0 by approximately minute 148 for the sushi meal. But glucose from sushi rice (and the fat/protein slowing gastric emptying) was clearly still being absorbed well past the 4-hour mark.

This solution uses the macro data already available at dose time (80g carb, 20g fat, 50g protein) to automatically extend the absorption model. When a meal has significant fat and protein alongside carbs, the system would:

- Split total carbs into a "fast" portion and a "slow/extended" portion
- Model fast carbs with the existing absorption curve
- Model slow carbs as a tail that trickles in over an extended period
- Optionally add fat-protein units (FPU) as additional "phantom carbs" absorbed over 4–8 hours

For the sushi meal, this might look like: 55g absorbed over the standard ~2-hour window, plus 25g "extended carbs" modeled as trickling in from hours 2–5, plus an additional 15–20g equivalent from fat-protein units absorbed over hours 3–6.

The `fattyMealEnabled` flag in the snapshot structure appears designed for something similar but was not enabled for this meal. This solution would either auto-enable based on macros or enhance what that flag does.

#### Expected Impact

Moderate to high, primarily through indirect effects. Extended COB awareness would prevent the loop from "giving up" on the meal too early. When the loop sees COB > 0, it factors remaining carb absorption into its predictions, which biases it toward maintaining or increasing insulin delivery rather than backing off. For the sushi meal, this would have prevented the loop from treating the situation as a pure correction scenario (where it's more conservative) and instead kept it in "active meal management" mode for longer.

The impact is somewhat dependent on how aggressively the loop acts on COB information, so this solution pairs well with Solution 1 (raised SMB caps) for maximum effect.

#### Practicality

Moderate. The core concept is well-established — fat-protein unit calculations have been used in the diabetes community for years (Warsaw/Krakow method). The challenge is calibrating the split ratios and extended absorption timing. These will vary by individual and even by specific food types. An initial implementation could use conservative defaults:

- **Trigger:** `(totalFat + totalProtein) > 30g` AND `totalCarbs > 40g`
- **Extended portion:** `min(30%, totalCarbs * (fat + protein) / (fat + protein + carbs))` of total carbs moved to extended absorption
- **Extension duration:** 3–5 hours beyond normal absorption, proportional to fat+protein content
- **FPU calculation:** `(fat × 9 + protein × 4) / 10` as grams of additional equivalent carbs, absorbed linearly over the extension period

These defaults would need tuning per-user, ideally with a settings screen to adjust sensitivity.

#### Safety Concerns & Guardrails

- **Over-estimation risk:** If the extended model overestimates remaining carbs, the loop will over-deliver insulin in the late post-meal window, potentially causing a delayed low 4–8 hours after the meal. This is the most common failure mode of fat-protein unit calculations.
- **Guardrail — conservative starting defaults:** Start with modest extended portions (20–25% of carbs extended) and let users tune upward based on experience.
- **Guardrail — BG floor check:** If BG drops below 120 mg/dL during the extended absorption window, zero out remaining phantom COB to prevent the loop from pushing more insulin when it's not needed.
- **Guardrail — actual vs. predicted reconciliation:** If actual BG is tracking significantly lower than predicted eventualBG during the extension window, decay the remaining phantom COB faster. The meal may not be absorbing as modeled.
- **Risk of complexity:** Users who don't understand the extended model may be confused when the loop behaves differently for "similar" carb counts. Clear UI communication about active extended absorption is important.

-----

### Solution 3: Sensitivity Ratio Cap Override

#### Description

The sensitivity ratio was capped at 1.2 for most of the sushi meal event. This cap determines how aggressively the loop treats insulin sensitivity — a ratio of 1.2 means the loop considers the user 20% more insulin-resistant than baseline, which adjusts ISF and carb ratio accordingly. Higher ratios drive more insulin delivery.

For meals flagged as "tough," the cap would be temporarily raised to 1.4 or 1.5 for the post-meal window. This effectively tells the loop: "each unit of insulin is going to be less effective for the next few hours, so deliver more."

#### Expected Impact

Moderate. The sensitivity ratio affects multiple calculations downstream — ISF, correction factor, and indirectly the SMB sizing. A cap increase from 1.2 to 1.4 would roughly translate to ~15–17% more insulin delivery across all the loop's correction and SMB calculations. For the sushi meal, this might have reduced peak BG by 20–30 mg/dL and shortened time above 180 by 60–90 minutes.

The effect is meaningful but not as dramatic as Solution 1 (raised SMB cap), because the sensitivity ratio is a multiplier on the overall calculation, not a direct constraint on per-cycle delivery. However, it stacks well with other solutions.

#### Practicality

High. This is a single parameter change — adjusting a cap value for a time-limited window. No algorithmic changes required. The sensitivity ratio infrastructure already exists and is well-tested.

One consideration: the autosens/Garmin blended sensitivity calculation that feeds into the ratio would continue to operate normally; only the ceiling on the final ratio would be raised. This means the loop's organic sensitivity detection still functions, it just has more headroom to express detected resistance.

#### Safety Concerns & Guardrails

- **Over-correction risk:** A higher sensitivity ratio means more insulin everywhere — SMBs, temp basals, correction calculations. If the user is not actually more resistant (e.g., they miscategorized the meal), this creates a blanket over-delivery that's harder to unwind than a single large SMB.
- **Guardrail — time limit:** Strictly enforce a 4–6 hour window. After expiry, immediately revert to the normal cap.
- **Guardrail — only raise the cap, don't set the ratio:** The sensitivity ratio should still be calculated normally by the autosens/Garmin system. Only the ceiling changes. If the system calculates 1.0, a raised cap to 1.4 doesn't force the ratio to 1.4 — it just allows it to go higher if the algorithm determines resistance is present.
- **Guardrail — pair with BG floor:** If BG drops below 100 mg/dL, override the raised cap back to the normal level regardless of time remaining.
- **Lower-risk than other solutions:** Because this modifies a multiplier rather than a hard delivery limit, the potential magnitude of error is somewhat bounded. A sensitivity ratio of 1.4 vs 1.2 is a ~17% difference, not a 3x difference like SMB cap changes.

-----

### Solution 4: Predictive Pre-Emptive Correction Bolusing

#### Description

This solution addresses the loop's fundamental reactive posture during post-meal spikes. Currently, the loop observes rising BG, calculates needed insulin, and delivers SMBs incrementally. By the time the corrections accumulate, BG is already at 290+.

The proposed approach: when the loop detects a specific combination of conditions, it delivers a larger "correction micro-bolus" — essentially a partial correction bolus that goes beyond normal SMB sizing, based on trusting the prediction model more aggressively during confirmed post-meal windows.

Trigger conditions (all must be true):

1. Active meal context (recent meal bolus within the last 3 hours, or COB > 0)
1. BG trending up (FortyFiveUp or SingleUp direction)
1. `eventualBG` exceeds a threshold (e.g., > 200 mg/dL)
1. Current BG already above target (e.g., > 140 mg/dL)

When triggered, the loop would calculate a correction dose based on `eventualBG` rather than current BG, and deliver up to 50% of that correction as an immediate bolus (subject to IOB and safety checks).

#### Expected Impact

Potentially high, but variable. The key insight is that the loop's `eventualBG` predictions were often quite accurate — during the sushi meal, `eventualBG` values of 200–400 were appearing while BG was still in the 160–200 range. If the loop had acted on those predictions with a 50% correction at minute 100 (when eventualBG was already showing 250+ and BG was around 180), it could have delivered 2–3u of additional correction insulin 30–60 minutes earlier than it actually did.

The challenge is that `eventualBG` predictions can be volatile and sometimes inaccurate, especially during rapid absorption phases. Acting too aggressively on predictions that turn out to be wrong creates risk.

#### Practicality

Moderate. The data needed for this decision is already computed every loop cycle (`eventualBG`, `insulinReq`, BG trend, COB). The implementation would add a new decision branch to the loop logic: "if these conditions are met, authorize a larger bolus." The complexity is in tuning the trigger thresholds and the correction fraction to avoid over-delivery.

This could be implemented as an enhancement to the existing SMB logic rather than a wholly new system — effectively, a conditional multiplier on SMB size when prediction confidence is high.

#### Safety Concerns & Guardrails

- **Prediction volatility:** `eventualBG` can swing wildly between loop cycles (in the sushi data, it jumped from 39 to 311 within a few cycles). Acting on a single high prediction could lead to over-correction.
- **Guardrail — smoothed predictions:** Require elevated `eventualBG` for 2–3 consecutive cycles before triggering pre-emptive correction. This filters out transient spikes in the prediction.
- **Guardrail — fraction limit:** Never deliver more than 50% of the calculated correction as a pre-emptive bolus. The remaining 50% should be delivered through normal SMB cadence as the situation develops.
- **Guardrail — IOB ceiling:** Hard-stop on pre-emptive dosing if IOB exceeds maxIOB × 0.8. Leave headroom for the loop to continue normal corrections.
- **Guardrail — one-shot with cooldown:** After delivering a pre-emptive correction, enter a cooldown period (e.g., 30–45 minutes) before allowing another. This prevents cascading pre-emptive doses if the prediction remains elevated while the first dose is still absorbing.
- **Higher implementation risk:** This solution introduces a new dosing pathway, which increases the testing and validation burden. Bugs or edge cases in the trigger logic could cause inappropriate bolusing in non-meal contexts.

-----

### Solution 5: Unified "Meal Intensity" System

#### Description

Rather than implementing individual toggles for each of the above solutions, create a unified scoring system that combines macro analysis, user input, and historical patterns to determine how aggressively the loop should manage a given meal.

At meal entry time, the system calculates a Meal Intensity Score:

|Factor                                          |Score|Example                        |
|------------------------------------------------|-----|-------------------------------|
|Carbs > 60g                                     |+1   |Sushi: 80g ✓                   |
|Fat > 15g                                       |+1   |Sushi: 20g ✓                   |
|Protein > 30g                                   |+1   |Sushi: 50g ✓                   |
|Macro ratio suggests extended absorption        |+1   |(fat+protein)/carbs > 0.5 ✓    |
|User manual "tough meal" flag                   |+1   |User toggle at dose time       |
|Historical: similar meals caused prolonged highs|+1   |Pattern matching from past data|

Based on the score, the system activates a tiered response:

**Score 1–2 (Moderate):**

- Mild extension of carb absorption model (+1–2 hours)
- Sensitivity ratio cap raised to 1.3
- SMB cap raised by 25%

**Score 3–4 (High):**

- Significant absorption extension (+2–4 hours with FPU modeling)
- Sensitivity ratio cap raised to 1.4
- SMB cap raised by 50–100%
- maxIOB raised by 20%

**Score 5+ (Extreme):**

- Full extended absorption modeling with aggressive FPU
- Sensitivity ratio cap raised to 1.5
- SMB cap raised by 100–200%
- maxIOB raised by 30%
- Pre-emptive correction bolusing enabled (Solution 4)

For the sushi meal, the score would have been at least 4 (80g carbs, 20g fat, 50g protein, macro ratio 0.875), triggering the "High" tier automatically — no user action required beyond entering accurate macros.

#### Expected Impact

This is the most comprehensive approach and would have the highest overall impact, because it layers multiple complementary solutions. Each individual solution addresses a different aspect of the problem (SMB cap addresses delivery speed, absorption modeling addresses awareness, sensitivity ratio addresses aggressiveness, prediction addresses timing), and combining them addresses the problem from all angles simultaneously.

For the sushi meal specifically, the combination of a "High" tier response would likely have reduced peak BG to the 230–260 range, shortened time above 180 to 150–200 minutes, and brought BG back under 180 by the 4-hour mark rather than the 8+ hour mark observed.

#### Practicality

Moderate to low for a v1 implementation. This requires building all four underlying mechanisms (Solutions 1–4) and a scoring/orchestration layer on top. However, a pragmatic approach would be to implement in phases:

- **Phase 1:** Solutions 1 + 3 (raised SMB cap and sensitivity cap) with a simple user toggle. Minimal code changes, immediate benefit.
- **Phase 2:** Solution 2 (extended absorption model) driven by macro data. Medium code complexity.
- **Phase 3:** Solution 4 (predictive correction) and the unified scoring system. Full integration with automatic tiering.

This phased approach delivers value at each step while building toward the complete system.

#### Safety Concerns & Guardrails

- **Compound risk:** Layering multiple aggressive adjustments simultaneously creates more total risk than any single change. If the macro data is wrong (user enters 80g carbs but only eats 40g), the system could over-deliver insulin through multiple independent channels.
- **Guardrail — unified kill switch:** A single BG threshold (e.g., BG < 110 mg/dL with downward trend) that immediately deactivates ALL meal intensity adjustments and reverts to normal parameters. This is simpler and safer than relying on each subsystem's individual guardrails.
- **Guardrail — transparency:** The app UI should clearly show the active meal intensity tier, the estimated time remaining, and which specific adjustments are active. Users need to be able to manually downgrade or cancel the tier if they realize the meal was smaller than expected.
- **Guardrail — learning loop:** Track outcomes for each meal intensity tier. If a user consistently goes low 4–6 hours after "High" tier meals, the system should suggest lowering the tier or adjusting the scoring thresholds. This could feed into the historical pattern matching.
- **Guardrail — conservative defaults:** Ship with all thresholds set conservatively. It's better for v1 to be slightly too cautious (user still goes high, but less so) than too aggressive (user experiences lows). Users can tune upward based on outcomes.

-----

## Recommended Implementation Priority

|Priority|Solution                                    |Effort     |Impact          |Risk                |
|--------|--------------------------------------------|-----------|----------------|--------------------|
|**1**   |Raised SMB + IOB caps (Solution 1)          |Low        |High            |Moderate            |
|**2**   |Sensitivity ratio cap override (Solution 3) |Low        |Moderate        |Low                 |
|**3**   |Extended absorption modeling (Solution 2)   |Medium     |Moderate-High   |Moderate            |
|**4**   |Predictive pre-emptive bolusing (Solution 4)|Medium-High|Potentially High|Higher              |
|**5**   |Unified Meal Intensity system (Solution 5)  |High       |Highest         |Managed via layering|

Solutions 1 and 3 can be implemented as a combined Phase 1 with a user toggle at meal time, delivering the majority of the benefit with minimal code changes. Solution 2 is the natural Phase 2, adding automatic intelligence. Solutions 4 and 5 represent the longer-term vision.

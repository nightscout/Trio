# Physiological Testing Mode

## Overview

A structured testing feature that allows the user to perform controlled meal experiments to build personalized carbohydrate absorption profiles. Rather than relying on population-based absorption models or noisy passive observation, this mode isolates variables and measures how the user's body actually absorbs carbohydrates under different macro compositions.

The primary goal is **absorption modeling**, not CR validation. The app learns the rate, shape, and timing of carbohydrate absorption for different meal compositions, enabling it to interpret real-time BG deltas and map them to actual carb absorption rates specific to the user.

---

## Objectives

1. **Build personalized absorption curves** — Capture the full BG response curve for pure carbs, carbs + fat, carbs + protein, and mixed meals
2. **Derive absorption rate signatures** — Extract first and second derivatives (rate of rise, acceleration/deceleration) from each test to parameterize absorption profiles
3. **Enable real-time carb inference** — Once absorption curves are stored, the app can pattern-match live BG movement against known profiles to estimate how many grams per minute are hitting the bloodstream
4. **Quantify macro modifiers** — Measure exactly how fat and protein reshape the absorption curve for this specific user, replacing population averages with personalized coefficients

---

## Prerequisites

### Ideal Testing Window

The user intermittent fasts on weekdays (eating window 3-9 PM). This creates a natural controlled environment from waking through early afternoon:

- No residual meal insulin on board
- No active digestion or gut variability
- Basal rate proving itself with stable, flat BG
- Hours of flat CGM data to anchor the pre-test baseline

**Recommended test time**: Late morning to early afternoon (e.g., 11 AM - 2 PM), allowing full observation before the normal eating window begins.

### Baseline Stability Requirement

Before a test can begin, the app must confirm BG stability:

- **Minimum flat period**: 60+ minutes of BG within +/- 3 mg/dL
- The longer the flat period, the higher confidence in the baseline — the user's IF pattern naturally provides multiple hours of flat data
- A short flat period (e.g., 15-20 minutes) is insufficient and may introduce error from drift, compression lows, or residual variability

### Automation Suspension

When test mode is entered:

- **SMBs are suspended** — no automatic micro-boluses during the test
- **Temp basals are suspended** — no automatic basal adjustments during the test
- **Normal scheduled basal continues** — this is the user's proven baseline and should remain constant
- The user delivers a single **manual bolus** based on their current best CR estimate for the test carbs

This isolates the test to: known carbs + known manual bolus + steady basal. No automation clouding the data.

---

## Test Protocol

### Step-by-Step

1. **Confirm baseline stability** — App verifies 60+ minutes of flat BG (within +/- 3 mg/dL)
2. **Enter test mode** — User activates the test, app suspends SMBs and temp basals
3. **Deliver manual bolus** — User gives their best-guess bolus for the test carbs (same dose all 4 test days to hold insulin constant)
4. **Eat the test meal** — User eats and logs the meal precisely, marking exact start time
5. **Observe** — App records the full BG curve: rise, peak, descent, return to flat
6. **Test ends** — When BG returns to flat for 30+ minutes, or the user manually exits

### Safety Exit

If BG drops below a low threshold or rises above a high threshold during the test, the app should:

- Alert the user immediately
- Offer to resume full automation (SMBs + temp basals) instantly
- Log the test as incomplete with the data collected up to that point

Test mode is informative — it is never worth a dangerous excursion.

---

## 4-Day Test Series

The series uses the **same carb count** on all 4 days (e.g., 30g carbs) and the **same manual bolus** on all 4 days. The only variable that changes is the macro composition.

### Day 1: Pure Carbs

- **Meal**: 30g carbs from a simple, consistent source (e.g., white rice, glucose tabs)
- **Purpose**: Establish the user's baseline carbohydrate absorption signature
- **What it measures**: Pure carb absorption rate, time to peak, curve shape without any macro interference

### Day 2: Carbs + Fat

- **Meal**: 30g carbs (same source as Day 1) + Xg fat (e.g., butter, olive oil)
- **Purpose**: Quantify how fat modifies the absorption curve
- **Expected effect**: Delayed absorption onset, reduced peak rate, extended absorption duration
- **What it measures**: Fat's specific delay factor, blunting of peak, elongation of the tail

### Day 3: Carbs + Protein

- **Meal**: 30g carbs (same source as Day 1) + Yg protein (e.g., chicken breast, whey isolate)
- **Purpose**: Quantify how protein modifies the absorption curve
- **Expected effect**: Potential co-stimulation of insulin response, possible modest delay, altered curve shape
- **What it measures**: Protein's absorption modifier, any insulin co-stimulation effect visible in the BG curve

### Day 4: Mixed Meal (Carbs + Fat + Protein)

- **Meal**: 30g carbs (same source) + Xg fat (same amount as Day 2) + Yg protein (same amount as Day 3)
- **Purpose**: Test whether combined macro effects are additive or nonlinear
- **Critical**: Use the exact same X and Y values from Days 2 and 3 — the only change is that all three macros are present together
- **What it measures**: The interaction effect — in most people, combined fat + protein delay is greater than the sum of individual delays, which is why mixed meals are difficult to bolus for

### Food Source Consistency

- **Carb source must be identical** all 4 days — same food, same preparation, same quantity
- **Fat source should be simple and measurable** — pure fat like butter or oil, easy to weigh precisely
- **Protein source should be lean and consistent** — minimize incidental fat or carbs from the protein source
- This minimizes variability so that differences between test curves are purely macro-driven

---

## Data Captured Per Test

### Raw Data

- Full CGM trace from baseline through return-to-flat
- Timestamps: test start, meal start, bolus time, test end
- Exact macro quantities logged (carbs, fat, protein in grams)
- Bolus amount (units)
- Active basal rate during test

### Derived Metrics

| Metric | Description |
|---|---|
| **Absorption onset delay** | Minutes from eating to first detectable BG rise |
| **Rate of rise (1st derivative)** | mg/dL per minute at each point on the curve — the absorption rate signal |
| **Acceleration (2nd derivative)** | Whether absorption is speeding up or slowing down at each point |
| **Peak absorption rate** | Maximum rate of BG rise, converted to estimated g/min carb absorption |
| **Time to peak rate** | When absorption is fastest (minutes after eating) |
| **Time to peak BG** | When total absorption starts losing to insulin clearance |
| **Total area under curve** | Integrated BG excursion above baseline — validates carb count against known intake |
| **Absorption duration** | Time from first rise to return to baseline |
| **Curve shape parameters** | Parameterized as a skewed gaussian or bilinear model (sharp vs gradual rise, symmetric vs asymmetric) |

### Comparative Metrics (Across Tests)

| Comparison | What It Reveals |
|---|---|
| **Day 2 vs Day 1** | Fat delay factor: onset shift, peak rate reduction %, duration extension |
| **Day 3 vs Day 1** | Protein modifier: onset shift, shape change, any insulin co-stimulation |
| **Day 4 vs Day 1** | Combined modifier: total reshaping of absorption curve |
| **Day 4 vs (Day 2 + Day 3)** | Nonlinearity: is the combined effect additive or synergistic? |

---

## How Test Results Feed Back Into the System

### Personalized Absorption Library

After completing the 4-day series, the app stores parameterized absorption curves:

- **Pure carb profile**: The user's baseline absorption signature
- **Fat modifier**: How adding fat reshapes the curve (delay, blunting, elongation)
- **Protein modifier**: How adding protein reshapes the curve
- **Combined modifier**: The actual interaction effect for mixed meals

These replace population-average absorption models with measured, personal values.

### Real-Time BG Interpretation

During normal operation (not test mode), the app uses stored absorption profiles to interpret live BG movement:

- Observes the current rate of BG rise (mg/dL per minute)
- Pattern-matches the rise shape against stored curves
- Infers: "This rise pattern looks like carbs + fat based on the slope and acceleration"
- Estimates actual carb absorption rate in g/min based on the user's proven profiles
- Feeds this into SMB and temp basal decisions with higher confidence

### High-Confidence Anchor Points

Test-derived data is treated as high-confidence calibration data, weighted significantly higher than passively observed meal data. While passive learning handles ongoing drift from noisy daily meals, test results provide ground-truth anchors that the system can reference.

---

## Retesting

### When to Retest

Absorption characteristics can shift over time due to:

- Changes in insulin sensitivity (seasonal, fitness, weight changes)
- Gut health or microbiome shifts
- Medication changes
- Significant lifestyle changes

### Suggested Cadence

- **Initial series**: 4 consecutive weekdays to build the baseline library
- **Periodic validation**: Single pure-carb test (Day 1 protocol) every 4-8 weeks to check for drift
- **Full retest**: Repeat the 4-day series if the single-test validation shows significant deviation from the stored profile, or after major lifestyle/health changes

---

## Future Considerations

- **Time-of-day variation**: Morning absorption may differ from evening. A future test series could repeat the protocol in different windows to capture circadian effects (e.g., dawn phenomenon impact on absorption)
- **Exercise interaction**: A test performed post-exercise vs rest could quantify how activity modifies absorption
- **Carb type comparison**: Same protocol but swapping the carb source (e.g., white rice vs whole grain vs fruit) to build absorption profiles per carb type
- **Dose-response**: Testing different carb quantities (15g vs 30g vs 60g) to check if absorption rate scales linearly or saturates

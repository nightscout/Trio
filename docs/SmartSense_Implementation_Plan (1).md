# Smart Sense Implementation Plan

## Overview

Smart Sense is a sensitivity adjustment system for the Trio insulin looping app that integrates Garmin wearable data and oref's autosens into a unified, user-controllable insulin sensitivity model. It replaces the naive "bolus multiplier" approach with a proper ISF/CR modification that the entire oref loop respects.

The system also integrates Cronometer meal detection via HealthKit, allowing users to select detected meals to prefill treatment data (carbs, fat, protein) and dose accordingly.

---

## Table of Contents

1. [Core Problem & Solution](#1-core-problem--solution)
2. [Treatment Flow](#2-treatment-flow)
3. [Smart Sense Sensitivity Model](#3-smart-sense-sensitivity-model)
4. [Garmin + Autosens Blending (Option C)](#4-garmin--autosens-blending-option-c)
5. [Weight System — Percentage Budget](#5-weight-system--percentage-budget)
6. [Sensitivity Slider Behavior](#6-sensitivity-slider-behavior)
7. [Delayed Dosing — Handling Absorption Head Start](#7-delayed-dosing--handling-absorption-head-start)
8. [Integration With oref](#8-integration-with-oref)
9. [Settings Screen](#9-settings-screen)
10. [Treatment Screen UI](#10-treatment-screen-ui)
11. [Data Export Schema](#11-data-export-schema)
12. [Garmin Data Source (Firebase)](#12-garmin-data-source-firebase)
13. [Watch Communication](#13-watch-communication)
14. [Key Design Decisions Log](#14-key-design-decisions-log)

---

## 1. Core Problem & Solution

### Why a Bolus Multiplier Does NOT Work

If the user eats 60g carbs and oref calculates a 6U bolus (CR=10), and Garmin says the user is 30% more resistant, a naive approach would deliver 7.8U instead. Here's what happens:

```
User eats 60g carbs. oref calculates 6U bolus (CR=10).
Garmin says +30% resistant → you give 7.8U instead.

What oref sees next loop cycle (5 min later):
  - IOB: 7.8U (high!)
  - Expected carb absorption: based on CR=10, needs 6U
  - Conclusion: "IOB exceeds needs, predict low"
  - Action: temp basal 0 for hours

Net result: you gave 7.8U upfront, oref withheld ~1.8U
in basal. You end up at roughly the same total insulin.
The override accomplished nothing.
```

### The Solution: Modify oref's Sensitivity Model

The Garmin factor must feed into oref as a **sensitivity ratio**, not a bolus multiplier. oref already supports this concept via autosens:

```
If sensitivity ratio = 1.20 (20% more resistant):
  ISF 40 → effective ISF 33.3  (40 / 1.20)
  CR  10 → effective CR  8.3   (10 / 1.20)
```

When oref uses adjusted ISF/CR, everything is consistent:

- Bolus calculator recommends more insulin (lower CR)
- Loop sees higher IOB but ALSO sees lower ISF → doesn't predict a low
- Temp basals and SMBs continue normally
- Corrections are appropriately sized

---

## 2. Treatment Flow

```
Treatments Screen Opens
        │
        ▼
  "Use a Cronometer meal?"
   ┌─────┴─────┐
  YES          NO
   │            │
   ▼            ▼
Meal Selection  Standard Treatments
(detected meals  (manual carb entry,
 from HealthKit)  bolus, etc.)
   │
   ▼
Selected meals prefill
Treatments page (carbs, fat, protein)
   │
   ▼
┌─ Smart Sense ─────────────────────────┐
│                                       │
│  Suggested: +9%                       │
│  ◄────────────●───────────►           │
│  -20%                  +20%           │
│                                       │
│  Garmin +12% (60%) + Autosens +4% (40%)│
│                                       │
│  Sleep 42/100 → +4.2%                 │
│  Yesterday 550cal → -3.1%             │
│  Body Battery 28 → +3.8%             │
│  Autosens (BG) → +1.6%               │
└───────────────────────────────────────┘
   │
   ▼
Bolus Recommendation: 5.7U
(ISF: 36.7, CR: 9.2 — adjusted from 40/10)
   │
   ▼
  [ Deliver ]
   │
   ▼
Meal marked isDosed ✓
(won't appear as undosed next time)
```

**Key points:**

- There is NO separate dose override slider. The user's only lever is the sensitivity slider.
- The user tells the system "how resistant am I" and oref does the math.
- Whatever oref recommends (using adjusted ISF/CR) is what gets delivered.

---

## 3. Smart Sense Sensitivity Model

### Architecture

```
Garmin Snapshot
      │
      ▼
Sensitivity Model (weighted factors)
      │
      ▼
Computed Garmin Factor: e.g., +12%
      │
      ▼
Blended with Autosens (per master split)
      │
      ▼
Treatment Screen Slider: user confirms or adjusts
      │
      ▼
Final Sensitivity Ratio: e.g., 1.09
      │
      ├──► Bolus Calculator: ISF/1.09, CR/1.09
      │         → recommends appropriate bolus
      │
      └──► oref loop (for override duration ~6h):
                uses adjusted ISF and CR
                → won't fight the bolus
                → temp basals, SMBs all consistent
```

### Continuous Operation

The Garmin factor adjusts oref's ISF/CR **continuously** — every loop cycle, all day. Bad sleep makes you resistant at breakfast AND dinner. If body battery recovers by afternoon, the factor naturally decreases.

This is like a smarter autosens that uses external leading data instead of just reactive BG history.

### Per-Dose Slider Override

At meal time, the user can bump the sensitivity adjustment higher or lower. This override **persists for 6 hours post-dose**, then reverts to the continuously computed value. This way the loop also respects the user's knowledge (e.g., pizza meals, coming illness, unknown workout).

---

## 4. Garmin + Autosens Blending (Option C)

**Decision: Option C — Both independent but user-weighted.**

### Rationale for Keeping Both

**Garmin catches (leading/predictive):**
- Bad sleep → resistance before BG shows it
- High stress → anticipates need
- Heavy exercise yesterday → next-day sensitivity shift
- Low body battery → general fatigue signal

**Autosens catches (reactive, things Garmin can't see):**
- Dawn phenomenon
- Illness onset before wearable metrics shift
- Hormonal cycles
- Pump site degradation
- Meal-specific absorption patterns

### Blending Mechanics

```
Garmin:    ±20% max (weighted by user factor preferences)
Autosens:  ±20% max (computed from BG history, 8-24h window)
Combined:  user sets a master split (e.g., 60% Garmin / 40% Autosens)
Final:     clamped to ±20%
```

**Formula:**

```
blendedAdjustment = (garminAdjust × garminSplit) + (autosensAdjust × autosenseSplit)
finalRatio = 1.0 + clamp(blendedAdjustment, -0.20, +0.20)
```

**Example:**

```
Garmin computed:  +12%
Autosens computed: +4%
Master split: 60/40

Blended = (+0.12 × 0.60) + (+0.04 × 0.40)
        = 0.072 + 0.016
        = +0.088 → rounded to +9%

Final ratio = 1.09
Effective ISF = 40 / 1.09 = 36.7
Effective CR  = 10 / 1.09 = 9.2
```

### Max Adjustment Range

**±20%** — same as the existing autosens cap that oref users are already comfortable with.

### Fallback Behavior

- If Garmin data is unavailable, autosens automatically gets 100% of the budget.
- The sensitivity slider still appears at 0% (neutral) and the user can manually adjust — they become their own "autosens."

---

## 5. Weight System — Percentage Budget

### How It Works

Users allocate a **100% budget** across Garmin signal categories. This controls what fraction of the ±20% budget (scaled by the Garmin portion of the master split) each signal can occupy.

**Mechanics:**

1. Each signal computes its own raw impact (e.g., sleep score 42 → "terrible" → raw impact of +0.08)
2. The weight determines what fraction of the budget that signal can occupy
3. If sleep quality is weighted at 30%, sleep alone can account for up to ±6% of the total ±20% (assuming 100% Garmin split)
4. All weighted impacts sum to produce the final Garmin composite factor

### Example Weight Configuration

```
Settings Screen:
┌─────────────────────────────────┐
│ Garmin Factor Weights           │
│ (must total 100%)               │
│                                 │
│ Sleep Quality      ███░░  30%   │
│ Sleep Duration     ██░░░  10%   │
│ Body Battery       ██░░░  15%   │
│ Stress (current)   █░░░░   5%   │
│ Stress (average)   █░░░░   5%   │
│ Resting HR Delta   █░░░░   5%   │
│ HRV Delta          █░░░░   5%   │
│ Yesterday Activity ████░  20%   │
│ Today Activity     █░░░░   5%   │
│ Vigorous Exercise  █░░░░   5%   │
│                    ──────────   │
│                    Total: 100%  │
└─────────────────────────────────┘
```

### Prioritization Example

If the user knows exercise is their #1 driver and sleep is #2:

```
Yesterday Activity: 50%  → can swing ±10% (of ±20%)
Sleep Quality:      30%  → can swing ±6%
Everything else:    20%  → can swing ±4%
Total possible:            ±20%
```

### Decision: Weights, Not Toggles

Weights were chosen over simple on/off toggles because the user needs to **prioritize** certain metrics — e.g., making sleep quality account for 50% of the score. Toggles don't allow this granularity.

The weights must total 100%, which forces tradeoffs and keeps the system bounded.

---

## 6. Sensitivity Slider Behavior

### Per-Dose Reset (Not Sticky)

**Decision: The slider resets to the computed (blended) value each time the treatment screen opens.**

Overrides are per-dose, not sticky between doses. Each time the user opens the treatment screen for a new meal, Smart Sense recalculates from the latest Garmin + autosens data and presents a fresh suggestion.

### Override Duration

**Decision: 6 hours post-dose.**

When the user adjusts the slider at dose time, the override persists for 6 hours so the loop also respects it. After 6h, it reverts to the continuously computed blended value.

### Export

Both the computed suggestion and the user's override value are exported for analysis, so the user can track how often they override and in which direction.

---

## 7. Delayed Dosing — Handling Absorption Head Start

### The Problem

A meal might be detected at 12:00 PM via Cronometer/HealthKit, but the user doesn't dose until 1:00 PM. In that hour, carbs have been absorbing and BG has been rising.

### How oref Handles This Naturally

When the user selects a meal detected at 12:00 PM and doses at 1:00 PM, the carb entry uses the **meal timestamp** (12:00), not the dose timestamp. oref's bolus calculator already accounts for:

- **IOB** — subtracts insulin already on board from automated SMBs/temp basals the loop may have delivered in response to the rising BG
- **BG correction** — current BG is higher than target, factored into recommendation
- **COB model** — knows carbs were entered at 12:00, models how much has absorbed

The bolus recommendation at 1:00 PM is naturally smaller than it would have been at 12:00 PM.

### What the Treatment Screen Shows

```
Treatment Screen (1:00 PM)
─────────────────────────────────────────

Selected: Lunch (65g carbs, 22g fat, 35g protein)
Meal time: 12:00 PM (60 min ago)
Current BG: 155 mg/dL  (was 110 at meal time)

┌─ Smart Sense ─────────────────────────┐
│                                       │
│  Suggested: +9%                       │
│  ◄────────────●───────────►           │
│  -20%                  +20%           │
│                                       │
│  Sleep 42 → +4.2%  |  Autosens → +1.6│
│  Activity → -3.1%  |  Body Bat → +3.8│
└───────────────────────────────────────┘

  Existing IOB: 1.2U (from SMBs since 12:00)
  Estimated absorbed: ~25g of 65g
  Remaining COB: ~40g

  Bolus Recommendation: 3.8U
  (adjusted ISF: 36.7, CR: 9.2)
  (accounts for 1.2U IOB already delivered)

  [ Deliver ]
```

### Export Captures Delay Details

The export includes `mealTimestamp`, `doseTimestamp`, `delayMinutes`, `bgAtMealDetection`, `bgRiseSinceMeal`, `iobAtDose`, `cobAtDose`, and `estimatedAbsorbed` — full traceability.

---

## 8. Integration With oref

### How the Factor Applies

Smart Sense modifies oref's ISF and CR via the sensitivity ratio. It does NOT apply as a bolus multiplier.

```
finalRatio = 1.0 + blendedAdjustment  (clamped to [0.80, 1.20])

effectiveISF = baseISF / finalRatio
effectiveCR  = baseCR / finalRatio
```

oref uses these adjusted values for:

- Bolus calculator recommendations
- Loop decisions (temp basals, SMBs)
- Correction calculations
- IOB/COB predictions

### Relationship to Autosens

Smart Sense's blended ratio **replaces** the standalone autosens ratio. Autosens is still computed, but its output is blended into Smart Sense via the master split — it no longer directly drives ISF/CR on its own. This prevents double-counting.

### Duration Layers

| Layer | Scope | Duration |
|-------|-------|----------|
| Continuous Garmin adjustment | Every loop cycle | Ongoing (recalculated each cycle) |
| Continuous autosens | Every loop cycle | 8–24h rolling window |
| Per-dose slider override | From dose time | 6 hours post-dose, then reverts to computed |

---

## 9. Settings Screen

```
Settings > Smart Sense
─────────────────────────────────────────

Master Split
  Garmin ◄████████████░░░░░░░► Autosens
         60%                40%

  (If Garmin unavailable, autosens
   automatically gets 100%)

Max Adjustment Range: ±20%

Garmin Factor Weights (must total 100%):
  Sleep Quality        ███████░░░  30%
  Sleep Duration       ███░░░░░░░  10%
  Body Battery         ███░░░░░░░  15%
  Stress (current)     ██░░░░░░░░   5%
  Stress (average)     ██░░░░░░░░   5%
  Resting HR Delta     ██░░░░░░░░   5%
  HRV Delta            ██░░░░░░░░   5%
  Yesterday Activity   █████░░░░░  20%
  Today Activity       ██░░░░░░░░   5%
  Vigorous Exercise    ██░░░░░░░░   5%
                       ────────────────
                       Total: 100%
```

### Garmin Signal Definitions

| Factor | Source | What It Measures | Positive = More Resistant |
|--------|--------|-----------------|--------------------------|
| Sleep Quality (Score) | Garmin sleep score (0–100) | Overall sleep quality | Low score → more resistant |
| Sleep Duration | Hours of sleep | Total sleep time | Short sleep → more resistant |
| Body Battery | Garmin Body Battery (0–100) | Energy reserves | Low battery → more resistant |
| Stress (current) | Current stress level (0–100) | Real-time stress | High stress → more resistant |
| Stress (average) | Average stress (time window) | Sustained stress | High avg → more resistant |
| Resting HR Delta | Delta from personal baseline | Autonomic state | Elevated HR → more resistant |
| HRV Delta | % change from personal average | Recovery/readiness | HRV below avg → more resistant |
| Yesterday Activity | Active calories burned yesterday | Prior-day energy expenditure | High activity → more sensitive (negative) |
| Today Activity | Active calories burned today | Same-day expenditure | High activity → more sensitive (negative) |
| Vigorous Exercise | Minutes of vigorous exercise | High-intensity work | Recent vigorous → more sensitive (negative) |

---

## 10. Treatment Screen UI

```
Treatment Screen
─────────────────────────────────────────

Selected Meal: Lunch (65g carbs, 22g fat, 35g protein)
Meal time: 12:00 PM (60 min ago)  ← shown if delayed
Current BG: 155 mg/dL

┌─ Smart Sense ─────────────────────────┐
│                                       │
│  Suggested: +9%                       │
│  ◄────────────●───────────►           │
│  -20%                  +20%           │
│                                       │
│  Garmin +12% (60%) + Autosens +4% (40%)│
│                                       │
│  Breakdown:                           │
│   Sleep Score 42      → +4.2%  (30%) │
│   Yesterday 550cal    → -3.1%  (20%) │
│   Body Battery 28     → +3.8%  (15%) │
│   Autosens (BG trend) → +1.6%  (40%) │
│   ...                                 │
└───────────────────────────────────────┘

  Existing IOB: 1.2U
  Remaining COB: ~40g

  Bolus Recommendation: 3.8U
  (ISF: 36.7, CR: 9.2 — adjusted from 40/10)

  [ Deliver ]
```

---

## 11. Data Export Schema

Every dosing decision exports the full decision context. This is critical for analysis and tuning.

```json
{
  "mealDecision": {
    "mealTimestamp": "2025-01-15T12:00:00Z",
    "doseTimestamp": "2025-01-15T13:00:00Z",
    "delayMinutes": 60,

    "selectedMeals": [
      {
        "label": "Lunch",
        "carbs": 65,
        "fat": 22,
        "protein": 35,
        "fiber": 8,
        "source": "cronometer",
        "detectedAt": "2025-01-15T12:00:00Z"
      }
    ],

    "stateAtDose": {
      "currentBG": 155,
      "bgAtMealDetection": 110,
      "bgRiseSinceMeal": 45,
      "iobAtDose": 1.2,
      "cobAtDose": 40,
      "estimatedAbsorbed": 25
    },

    "smartSense": {
      "garminFactors": [
        {
          "factor": "Sleep Score",
          "value": "42/100",
          "rawImpact": 0.08,
          "weight": 0.30,
          "weightedImpact": 0.042
        },
        {
          "factor": "Yesterday Activity",
          "value": "550 cal",
          "rawImpact": -0.05,
          "weight": 0.25,
          "weightedImpact": -0.019
        },
        {
          "factor": "Body Battery",
          "value": "28/100",
          "rawImpact": 0.06,
          "weight": 0.15,
          "weightedImpact": 0.015
        },
        {
          "factor": "HRV Delta",
          "value": "-18%",
          "rawImpact": 0.02,
          "weight": 0.05,
          "weightedImpact": 0.002
        },
        {
          "factor": "Sleep Duration",
          "value": "5h 12m",
          "rawImpact": 0.03,
          "weight": 0.10,
          "weightedImpact": 0.005
        },
        {
          "factor": "Current Stress",
          "value": "62/100",
          "rawImpact": 0.02,
          "weight": 0.05,
          "weightedImpact": 0.002
        },
        {
          "factor": "Avg Stress",
          "value": "48/100",
          "rawImpact": 0.02,
          "weight": 0.05,
          "weightedImpact": 0.002
        },
        {
          "factor": "Resting HR Delta",
          "value": "+3 bpm",
          "rawImpact": 0.0,
          "weight": 0.05,
          "weightedImpact": 0.0
        },
        {
          "factor": "Today Activity",
          "value": "180 cal",
          "rawImpact": 0.0,
          "weight": 0.05,
          "weightedImpact": 0.0
        },
        {
          "factor": "Vigorous Exercise",
          "value": "0 min",
          "rawImpact": 0.0,
          "weight": 0.05,
          "weightedImpact": 0.0
        }
      ],
      "garminComposite": 0.12,
      "autosensRatio": 1.04,
      "autosensContribution": 0.04,
      "masterSplit": {
        "garmin": 0.60,
        "autosens": 0.40
      },
      "blendedSuggestion": 0.088,
      "userOverride": 0.09,
      "overrideWasModified": true,
      "finalRatio": 1.09,
      "baseISF": 40,
      "effectiveISF": 36.7,
      "baseCR": 10,
      "effectiveCR": 9.2,
      "overrideDuration": "6h",
      "overrideExpiry": "2025-01-15T19:00:00Z"
    },

    "userSettings": {
      "maxAdjustment": 0.20,
      "masterSplit": {
        "garmin": 0.60,
        "autosens": 0.40
      },
      "factorWeights": {
        "sleepScore": 0.30,
        "sleepDuration": 0.10,
        "bodyBattery": 0.15,
        "currentStress": 0.05,
        "avgStress": 0.05,
        "restingHRDelta": 0.05,
        "hrvDelta": 0.05,
        "yesterdayActivity": 0.25,
        "todayActivity": 0.05,
        "vigorousExercise": 0.05
      },
      "baseISF": 40,
      "baseCR": 10,
      "target": 100
    },

    "dose": {
      "recommended": 3.8,
      "delivered": 3.8,
      "preDoseIOB": 1.2,
      "preDoseCOB": 40
    },

    "postMealTrace": {
      "bgReadings": [
        {"time": "2025-01-15T13:00:00Z", "bg": 155, "minutesPostDose": 0},
        {"time": "2025-01-15T13:05:00Z", "bg": 162, "minutesPostDose": 5},
        {"time": "2025-01-15T13:10:00Z", "bg": 168, "minutesPostDose": 10}
      ],
      "insulinDelivery": [
        {"time": "2025-01-15T13:00:00Z", "type": "bolus", "amount": 3.8},
        {"time": "2025-01-15T13:25:00Z", "type": "smb", "amount": 0.3},
        {"time": "2025-01-15T13:30:00Z", "type": "tempBasal", "rate": 1.8, "duration": 30}
      ],
      "loopDecisions": [
        {
          "time": "2025-01-15T13:05:00Z",
          "eventualBG": 175,
          "iob": 4.2,
          "cob": 38,
          "sensitivityRatio": 1.09
        },
        {
          "time": "2025-01-15T13:10:00Z",
          "eventualBG": 170,
          "iob": 4.0,
          "cob": 35,
          "sensitivityRatio": 1.09
        }
      ],
      "traceDurationHours": 8,
      "bgAtPeak": 195,
      "peakTime": "2025-01-15T14:15:00Z",
      "minutesToPeak": 75,
      "bgAt2h": 142,
      "bgAt4h": 108,
      "bgAt6h": 98,
      "timeInRange": 0.72,
      "timeBelowRange": 0.0
    }
  }
}
```

### Key Export Details

- Every loop decision in `postMealTrace` includes the `sensitivityRatio` so you can verify the 6h Smart Sense override was active
- `overrideWasModified` tracks whether the user moved the slider from the computed suggestion
- `bgReadings` captures all BG after dosing for outcome analysis
- `insulinDelivery` captures boluses, SMBs, and temp basals — the full picture of what the loop did
- `userSettings` snapshot captures the configuration at time of dosing

---

## 12. Garmin Data Source (Firebase)

Garmin data is stored in a **separate Firebase Realtime Database**. Secrets are already configured in GitHub.

### Data Points Retrieved From Firebase

The following Garmin metrics must be available for the Smart Sense model:

| Metric | Type | Source |
|--------|------|--------|
| Sleep Score | 0–100 integer | Garmin sleep tracking |
| Sleep Duration | Minutes or hours | Garmin sleep tracking |
| Body Battery | 0–100 integer | Garmin Body Battery |
| Current Stress | 0–100 integer | Garmin stress tracking |
| Average Stress | 0–100 integer | Garmin stress (rolling window) |
| Resting Heart Rate | BPM integer | Garmin HR monitoring |
| Resting HR Baseline | BPM integer | Personal average (computed) |
| HRV | Milliseconds | Garmin HRV tracking |
| HRV Baseline | Milliseconds | Personal average (computed) |
| Yesterday Active Calories | Integer | Garmin activity tracking |
| Today Active Calories | Integer | Garmin activity tracking |
| Vigorous Exercise Minutes | Integer | Garmin activity intensity |

### Delta Calculations

Some factors use deltas from personal baselines:

- **Resting HR Delta** = current resting HR − personal baseline resting HR
- **HRV Delta** = (current HRV − personal average HRV) / personal average HRV × 100 (expressed as % change)

These baselines should be computed as rolling averages from historical Garmin data in Firebase.

---

## 13. Watch Communication

The Garmin watch communicates data to the phone app via Firebase as an intermediary. The watch app pushes snapshots to Firebase; the phone app reads from Firebase.

Ensure the system handles:

- Stale data (watch hasn't synced recently) — show data age on treatment screen
- Missing fields (not all metrics available every day)
- Firebase connectivity issues — graceful fallback to autosens-only mode

---

## 14. Key Design Decisions Log

This section captures all decisions made during the design conversation for future reference.

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 1 | Weights vs toggles for Garmin factors? | **Weights (percentage budget, must total 100%)** | Users need to prioritize certain metrics (e.g., sleep = 50%). Toggles don't allow this. |
| 2 | Slider resets per dose vs sticky? | **Reset per dose** | Slider recomputes from latest data each time treatment screen opens. Overrides are per-dose, not sticky. |
| 3 | Where does the factor apply? | **Modifies oref's ISF/CR (sensitivity ratio)** | Bolus multiplier doesn't work — oref fights it with zero temp basals. Must change what oref believes about sensitivity. |
| 4 | Continuous vs meal-only adjustment? | **Continuous** | If you're resistant, corrections should also be larger. The Garmin factor adjusts every loop cycle, all day. |
| 5 | Override duration at dose time? | **6 hours** | Covers typical meal absorption window. Reverts to continuously computed value after. |
| 6 | Autosens interaction? | **Option C — Both independent, user-weighted, shared ±20% budget** | Garmin is predictive (leading). Autosens is reactive (catches things Garmin can't — dawn phenomenon, site issues, illness). User controls the split. |
| 7 | Max adjustment range? | **±20%** | Matches existing autosens cap. Users are already comfortable with this range. |
| 8 | Dose override slider? | **No** | Removed. The user's only lever is the sensitivity slider. They tell the system their resistance level; oref calculates the dose. |
| 9 | Weight budget constrained or independent? | **Constrained (must total 100%)** | Forces tradeoffs. Prevents unbounded signal stacking. |
| 10 | Fallback when Garmin unavailable? | **Autosens gets 100%. Slider still available at 0% for manual adjustment.** | User becomes their own "autosens" via the slider. |

---

## System Summary

| Layer | What It Does | Persists | User Control |
|-------|-------------|----------|-------------|
| Garmin factors | Computes sensitivity from wearable data | Continuous (recalc each loop) | Weight allocation in settings |
| Autosens | Computes sensitivity from BG history | Continuous (8–24h window) | Master split % in settings |
| Blended ratio | Combines Garmin + autosens per split | Continuous | Master split slider |
| Sensitivity override | User adjusts blended value at dose time | 6h post-meal | Slider on treatment screen |
| ISF/CR modification | Final ratio applied to oref's ISF and CR | Matches override duration | Indirect (via above layers) |

Everything exports: computed values, user overrides, factor breakdowns, actual delivery, post-meal BG trace, and loop decisions. Full traceability for tuning.

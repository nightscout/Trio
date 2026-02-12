# Trio Feature Game Plan

## Where We Are

### Already Built (on Profiles-AI-Quick-Carbs)

| Feature | Status | Key Files |
|---------|--------|-----------|
| **Therapy Profiles** | Done | `TherapyProfile.swift`, `ProfileManager.swift`, editor/list UI |
| **AI Insights** | Done | `ClaudeAPIService.swift`, `HealthDataExporter.swift`, 6 analysis types |
| **Photo Carb Estimation** | Done | Vision API in ClaudeAPIService |
| **Why High/Low Banner** | Done | Home screen banner + 4-6h focused analysis |
| **Claude-o-Tune** | Done | AI-powered profile optimization with safety guardrails |
| **Health Metrics in AI** | Done | Apple Health (steps, sleep, HR, HRV, workouts) in prompts |
| **Garmin Watch Comms** | Done | `GarminManager.swift` — glucose/IOB/COB/trend to watch |

### Not Yet Built (spec'd in docs/)

| Feature | Spec Document | Dependency |
|---------|--------------|------------|
| **Garmin Firestore fetch** | `GARMIN_INTEGRATION_SPEC.md` | Firebase SDK, build-time secrets |
| **Garmin Sensitivity Model** | `GARMIN_INTEGRATION_SPEC.md` | Garmin Firestore data |
| **SmartSense Engine** | `SmartSense_Implementation_Plan.md` | Garmin Sensitivity + Autosens |
| **Cronometer Meal Detection** | `MEAL_DETECTION_AND_SELECTION_SPEC.md` | HealthKit nutrition observer |
| **Meal Selection UI** | `MEAL_DETECTION_AND_SELECTION_SPEC.md` | Meal detection engine |
| **Smart Sense Slider** | `SmartSense_Implementation_Plan.md` | SmartSense engine |
| **Meal Decision Export** | `MEAL_DECISION_EXPORT_SPEC.md` | Meal selection + SmartSense |
| **V2 Comprehensive Export** | `EXPORT_JSON_SPEC.md` | All above features |

---

## Implementation Phases

The SmartSense plan is the unifying vision. Everything feeds into it. The phases below are ordered by dependency — each phase unlocks the next.

---

### Phase 1: Cronometer Meal Detection

**Goal:** Detect meals logged in Cronometer (or any HealthKit nutrition writer) and present them for selection on the treatment screen.

**Why first:** This is self-contained, has no dependency on Garmin or SmartSense, and immediately improves the daily dosing workflow. Users get quick carb entry from Cronometer instead of manual typing.

**What to build:**

1. **Data Models**
   - `V2DetectedMeal` — UI-facing meal (date, label, carbs, fat, protein, fiber, source, isDosed)
   - `NutritionSnapshot` — point-in-time cumulative HealthKit totals with observer timestamp
   - `InferredMealEvent` — meal derived from snapshot delta
   - `HealthNutritionEntry` — unified nutrition entry

2. **HealthKit Nutrition Observer**
   - `NutritionHealthService` protocol + implementation
   - `HKObserverQuery` for carbs, fat, protein, fiber
   - Background delivery registration
   - On observer fire: query cumulative totals, save snapshot with current timestamp

3. **Snapshot Store & Meal Inference Engine**
   - `NutritionSnapshotStore` (singleton)
   - Snapshot delta computation (consecutive diffs, >1g threshold)
   - 15-minute merge window for raw deltas
   - Dose boundary detection (don't merge across doses)
   - Meal labeling (Breakfast/Lunch/Dinner/Snack by time-of-day)

4. **Treatment Screen Integration**
   - "Use a Cronometer meal?" entry point on treatments page
   - Meal feed with checkboxes for selection
   - `V2MealCardView` — individual meal display (time, macros, source)
   - `V2ManualMealEntryView` — manual macro entry fallback
   - On "Continue": combined carbs populate standard oref carbs field
   - Standard bolus calculator takes over from there

5. **Settings**
   - Toggle: Enable Cronometer Meal Detection
   - HealthKit nutrition permissions request

**Integration point:** Selected meal carbs → `state.carbs` → standard oref bolus calculator. No changes to oref itself.

**Spec reference:** `docs/MEAL_DETECTION_AND_SELECTION_SPEC.md`

---

### Phase 2: Garmin Health Data (Firestore)

**Goal:** Fetch Garmin wearable health data (sleep, stress, HRV, body battery, activity) from the user's Firebase/Firestore database.

**Why second:** Provides the raw data that the sensitivity model needs. Independent of meal detection — can develop in parallel if desired.

**What to build:**

1. **Firebase Configuration**
   - `GarminFirebaseConfig.swift` — build-time placeholder values for Firebase project
   - `isConfigured` check (if placeholders still present → gracefully disable)
   - CI workflow: `sed` replacement of `__GARMIN_FIREBASE_*__` placeholders from GitHub secrets

2. **Firebase Authentication**
   - Create named FirebaseApp ("garmin") with user's project credentials
   - Email/password sign-in using build-time injected credentials
   - `isSignedIn` flag — all downstream code checks this before querying

3. **Firestore Service**
   - `GarminFirestoreService` — queries Firestore for health data
   - Document structure: `users/{uid}/garminData/{collection}/dates/{YYYY-MM-DD}`
   - Collections: `dailySummaries`, `sleep`, `stressDetails`, `hrv`, `userMetrics`
   - Query today's data + yesterday's data (for activity comparisons)
   - Handle missing fields, stale data, connectivity issues

4. **Data Model**
   - `GarminContextSnapshot` — ~40 health fields in one struct
   - Sleep: score, duration, deep/light/REM minutes, sleep start/end
   - Stress: current, average, max, time in ranges
   - HRV: current, 7-day average, weekly status
   - Body Battery: current, high, low, charged/drained
   - Activity: active calories (today + yesterday), steps, vigorous minutes, intensity minutes
   - Heart Rate: resting, average, min, max

5. **Baseline Computation**
   - Rolling averages for resting HR and HRV (personal baselines)
   - Delta calculations: current vs. baseline
   - Store/retrieve baselines from UserDefaults or local file

6. **Settings UI**
   - Garmin Health Data toggle (separate from existing Garmin Watch toggle)
   - Firebase connection status indicator
   - Data freshness indicator (last sync time)

**Spec reference:** `docs/GARMIN_INTEGRATION_SPEC.md` §1-5

---

### Phase 3: SmartSense Engine

**Goal:** Build the core sensitivity model that blends Garmin health signals with oref's autosens into a unified sensitivity ratio, and expose it via a slider on the treatment screen.

**Why third:** This is the keystone feature. It requires Garmin data (Phase 2) and benefits from meal detection (Phase 1) for the complete treatment flow.

**What to build:**

1. **Garmin Sensitivity Model**
   - `GarminSensitivityModel` — 10-signal weighted computation
   - Input: `GarminContextSnapshot`
   - Each signal: threshold-based tier → raw impact value
   - Signal thresholds (from spec):
     - Sleep Score: <40 → -11%, <55 → -8%, <70 → -4%, ≥85 → +3%
     - Body Battery: <15 → -9%, <30 → -6%, <50 → -3%, ≥75 → +3%
     - Yesterday Activity: >600cal → +8%, >400 → +5%, >250 → +3%
     - (all 10 signals per spec §6)
   - Weight allocation: user's percentage budget (must total 100%)
   - Output: Garmin composite factor (e.g., +12%)

2. **Blending Engine**
   - `SmartSenseEngine` — combines Garmin + Autosens
   - Garmin composite × garmin split + autosens adjustment × autosens split
   - Master split: user-configurable (e.g., 60/40)
   - Clamp result to ±20%
   - Fallback: if Garmin unavailable → autosens gets 100%
   - Output: `finalRatio` (e.g., 1.09)

3. **Per-Dose Override**
   - Slider value stored with dose timestamp
   - Override persists for 6 hours post-dose
   - After expiry: reverts to continuously computed value
   - Each treatment screen open: slider resets to fresh computed suggestion

4. **oref Integration**
   - Feed `finalRatio` as sensitivity ratio into oref's ISF/CR
   - `effectiveISF = baseISF / finalRatio`
   - `effectiveCR = baseCR / finalRatio`
   - Replaces standalone autosens ratio (prevents double-counting)
   - Applies every loop cycle, continuously

5. **Treatment Screen UI**
   - Smart Sense card showing:
     - Suggested adjustment (e.g., "+9%")
     - Slider: -20% to +20%
     - Garmin + Autosens breakdown with percentages
     - Individual factor contributions (sleep, activity, body battery, etc.)
   - Below the slider: adjusted ISF/CR values, bolus recommendation
   - Integrates with meal selection from Phase 1

6. **Settings Screen**
   - Master Split slider (Garmin ↔ Autosens)
   - Max adjustment range display (±20%)
   - Garmin Factor Weights (10 sliders, must total 100%)
   - Visual budget allocation with remaining percentage

**Spec reference:** `docs/SmartSense_Implementation_Plan.md` §3-10

---

### Phase 4: Meal Decision Export

**Goal:** Capture everything about each dosing decision and its 8-hour outcome for analysis and tuning.

**Why fourth:** Requires both meal detection (Phase 1) and SmartSense (Phase 3) to capture full decision context. This is the feedback loop that makes the system learnable.

**What to build:**

1. **At-Dose-Time Capture**
   - `MealDecisionRecord` — comprehensive snapshot at bolus confirmation:
     - Selected meals (date, label, macros, source)
     - BG state (current, delta, trend)
     - Pump settings (ISF, CR, target, basal, max bolus/IOB)
     - Algorithm state (IOB, COB, eventual BG, sensitivity ratio)
     - Calculator breakdown (all intermediate values)
     - SmartSense breakdown (every factor, weights, computed vs. user override)
     - Recommended vs. actual dose
   - Store in Core Data on dose confirmation

2. **Post-Meal Trace Collection**
   - Background task: collect 8 hours of post-meal data
   - BG readings (every CGM point)
   - SMBs, manual boluses, temp basals
   - Loop decisions (~5 min intervals with IOB, COB, eventual BG, sensitivity ratio)
   - Summary statistics (peak BG, nadir, time to peak, time in range)

3. **Export System**
   - `MealDecisionExport` — JSON encoder for all records
   - Root object: export date, app version, array of records
   - Share sheet integration (system UIActivityViewController)
   - Configurable date range

4. **Delayed Dosing Context**
   - `mealTimestamp` vs. `doseTimestamp` with `delayMinutes`
   - BG at meal detection vs. BG at dose
   - IOB accumulated from automated delivery during the delay
   - Estimated carbs absorbed before dosing

**Spec reference:** `docs/MEAL_DECISION_EXPORT_SPEC.md`

---

### Phase 5: V2 Comprehensive Export & AI Integration

**Goal:** Full 90-day export combining meals, BG, insulin, SmartSense, and Garmin data. Plus wire SmartSense context into AI analysis prompts.

**Why last:** This is the capstone — it needs all prior features to capture complete data.

**What to build:**

1. **V2 Comprehensive Meal Export (JSON)**
   - 90 days of meal outcomes
   - Per-meal: 2h pre-meal + 8h post-meal glucose
   - Macros, boluses, temp basals, loop decisions
   - Garmin context and SmartSense contributions per meal
   - V2 settings snapshot
   - Export to `.json` file via share sheet

2. **SmartSense Context in AI Prompts**
   - Extend `HealthDataExporter` to include SmartSense data
   - Garmin health signals in analysis context
   - Sensitivity ratio history over analysis period
   - User override patterns (how often, which direction, meal types)

3. **Export Settings UI**
   - "Export All Meal Data" button
   - Date range selector
   - Include/exclude toggles for Garmin data, SmartSense breakdown

**Spec reference:** `docs/EXPORT_JSON_SPEC.md`

---

## Dependency Graph

```
Phase 1: Meal Detection ─────────────────────────────┐
  (Cronometer → HealthKit → Snapshots → Meal Feed)   │
                                                      ├──► Phase 4: Meal Decision Export
Phase 2: Garmin Health Data ──┐                       │      (at-dose capture + 8h trace)
  (Firestore → Snapshot)      │                       │
                              ├──► Phase 3: SmartSense│
Phase 0 (done): Autosens ────┘     (blending engine,  ├──► Phase 5: Comprehensive Export
                                    slider, oref       │      (90-day JSON + AI context)
                                    integration)  ────┘
```

## Treatment Flow (All Phases Combined)

```
User opens Treatments
        │
        ▼
"Use a Cronometer meal?"          ◄── Phase 1
   ┌────┴────┐
  YES        NO
   │          │
   ▼          ▼
Meal Feed    Manual Entry
(select meals)
   │
   ▼
Selected macros prefill carbs/fat/protein
   │
   ▼
┌─ Smart Sense ──────────────────┐  ◄── Phase 3
│  Suggested: +9%                │
│  ◄────────●───────────►        │
│  -20%              +20%       │
│                                │
│  Garmin +12% + Autosens +4%   │  ◄── Phase 2
│  Sleep 42 → +4.2%             │
│  Activity 550cal → -3.1%      │
│  Body Battery 28 → +3.8%      │
└────────────────────────────────┘
   │
   ▼
Bolus Recommendation: 5.7U
(ISF: 36.7, CR: 9.2)
   │
   ▼
[ Deliver ]
   │
   ├──► Decision captured          ◄── Phase 4
   └──► 8h trace begins            ◄── Phase 4
```

## Parallel Work Opportunities

Phases 1 and 2 have **zero dependency on each other** and can be developed simultaneously:

- **Stream A:** Meal Detection (Phase 1) — pure HealthKit/SwiftUI work
- **Stream B:** Garmin Firestore (Phase 2) — Firebase/networking work

Phase 3 (SmartSense) requires Phase 2 output but can start with autosens-only mode (Garmin fallback path) while Phase 2 completes.

---

## Risk Areas

| Risk | Mitigation |
|------|-----------|
| HealthKit observer reliability (background delivery) | Test with multiple nutrition apps, not just Cronometer |
| Cronometer midnight timestamps | Snapshot system captures observer fire time, not HealthKit sample time |
| Firebase auth complexity (named app, build-time secrets) | Graceful disable if not configured; autosens-only fallback |
| Garmin data staleness (watch not synced) | Show data age on treatment screen; fall back to autosens |
| oref sensitivity ratio injection | Use existing autosens pathway; don't create a parallel mechanism |
| Weight budget UX (10 sliders summing to 100%) | Consider linked sliders or a "distribute remaining" pattern |
| 6-hour override expiry during sleep | Continuous Garmin factor still active; override is additive context |

---

## Files to Create (Estimated)

### Phase 1 (~10-12 files)
- `V2DetectedMeal.swift`
- `NutritionSnapshot.swift`
- `InferredMealEvent.swift`
- `NutritionHealthService.swift`
- `NutritionSnapshotStore.swift`
- `V2TreatmentView.swift` (meal feed container)
- `V2MealCardView.swift`
- `V2ManualMealEntryView.swift`
- Treatment screen integration edits
- Settings toggle additions

### Phase 2 (~6-8 files)
- `GarminFirebaseConfig.swift`
- `GarminFirestoreService.swift`
- `GarminContextSnapshot.swift`
- `GarminBaselineStore.swift`
- Settings UI additions
- CI workflow edits (secret injection)

### Phase 3 (~6-8 files)
- `GarminSensitivityModel.swift`
- `SmartSenseEngine.swift`
- `SmartSenseSliderView.swift`
- `SmartSenseSettingsView.swift`
- oref integration edits (sensitivity ratio injection)
- Treatment screen edits (slider integration)

### Phase 4 (~4-5 files)
- `MealDecisionRecord.swift`
- `MealDecisionExporter.swift`
- `PostMealTraceCollector.swift`
- Core Data model additions
- Export UI

### Phase 5 (~3-4 files)
- `V2ComprehensiveExport.swift`
- HealthDataExporter extensions
- Export settings UI

# Export JSON Specification — Macros, Treatments, BG

This document describes the two JSON/data export systems in Trio: the **V2 Comprehensive Meal Export** (machine-readable JSON file) and the **AI Health Data Export** (text-formatted prompt with structured data). Both combine macros, treatment data, and blood glucose into a single export.

---

## Table of Contents

1. [Export Systems Overview](#1-export-systems-overview)
2. [V2 Comprehensive Meal Export (JSON)](#2-v2-comprehensive-meal-export-json)
3. [AI Health Data Export (Text/Prompt)](#3-ai-health-data-export-textprompt)
4. [Core Data Entities Used](#4-core-data-entities-used)
5. [File Inventory](#5-file-inventory)

---

## 1. Export Systems Overview

| Feature | V2 Meal Export | AI Health Data Export |
|---------|---------------|---------------------|
| **Format** | JSON file (`.json`) | Formatted text (prompt string) |
| **Trigger** | "Export All Meal Data" button | AI Insights analysis types |
| **Sharing** | `UIActivityViewController` (system share sheet) | Sent to Claude API directly |
| **Data Scope** | 90 days of meal outcomes | Configurable: 1-90 days |
| **BG Data** | 2h pre-meal + 8h post-meal per meal | Full CGM trace for period |
| **Macros** | Per-meal carbs/fat/protein/fiber | Carb entries with fat/protein |
| **Treatment Data** | Boluses, temp basals, loop decisions per meal | Boluses, loop states for period |
| **Settings** | Full V2 + oref settings snapshot | Full settings + schedules |
| **Health Metrics** | Garmin context (sleep, stress, HRV) | Apple Health (activity, sleep, HR, HRV, workouts) |
| **Encoding** | `JSONEncoder` with ISO8601 dates | `DateFormatter` "MM/dd HH:mm" |
| **File** | `V2CurveOutcomeLearning.swift` | `HealthDataExporter.swift` |

---

## 2. V2 Comprehensive Meal Export (JSON)

**Source:** `Trio/Sources/Services/V2CurveOutcomeLearning.swift`
**UI:** `Trio/Sources/Modules/Settings/View/Subviews/V2OutcomeAnalysisView.swift`

### How the Export is Triggered

From the "Outcome Accuracy" settings page, user taps "Export All Meal Data":

```swift
private func exportAllData() {
    isExporting = true
    Task {
        let context = CoreDataStack.shared.newTaskContext()
        let export = await V2OutcomeLearningStore.shared.buildComprehensiveExport(context: context)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(export) else { return }

        let dateStr = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "v2-meal-export-\(dateStr).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try data.write(to: tempURL)
        // Present UIActivityViewController with the file URL
    }
}
```

**Output filename:** `v2-meal-export-2026-02-12T14-30-45Z.json`

### Complete JSON Schema

#### Root: `V2ComprehensiveExport`

```json
{
  "exportDate": "2026-02-12T14:30:45Z",
  "appVersion": "1.2.3",
  "totalMeals": 42,
  "currentParameters": { /* V2PersonalCurveParameters */ },
  "userSettings": { /* V2UserSettingsSnapshot */ },
  "meals": [ /* [V2MealExportRecord] */ ]
}
```

#### `V2UserSettingsSnapshot`

Captures all settings that affect dosing at the moment of export:

```json
{
  "useV2MacroAbsorption": true,
  "insulinType": "rapidActing",
  "v2SafeWindowMinutesOverride": null,
  "mealModeSMBMultiplier": 2.0,
  "mealModeBGFloor": 80.0,
  "garminEnabled": true,
  "v2OutcomeLearningEnabled": true,
  "claudeRecalibrationEnabled": false,

  "maxIOB": 8.0,
  "maxSMBBasalMinutes": 30.0,
  "maxUAMSMBBasalMinutes": 30.0,
  "smbDeliveryRatio": 0.5,
  "smbInterval": 3.0,
  "insulinCurve": "rapidActing",
  "insulinPeakTime": 75.0,
  "useCustomPeakTime": false,
  "maxCOB": 120.0,
  "enableSMBAlways": true,
  "enableSMBWithCOB": true,
  "enableSMBAfterCarbs": true,
  "enableUAM": true,
  "autosensMax": 1.2,
  "autosensMin": 0.7
}
```

Settings are gathered from two sources:
- `TrioSettings` (via `BaseFileStorage`) — V2 engine settings
- `Preferences` (via `BaseFileStorage`) — OpenAPS/oref settings

#### `V2PersonalCurveParameters`

Learned curve parameters (or defaults if not yet learned):

```json
{
  "carbTau": 35.0,
  "proteinThreshold": 15.0,
  "proteinPlateau": 40.0,
  "proteinFactor": 0.35,
  "fatTotalCoeff": 0.69,
  "fiberCoefficient": 0.30
}
```

#### `V2MealExportRecord` — One Per Meal

Each meal in the `meals` array contains everything the system knew and did:

```json
{
  "outcome": { /* V2MealOutcome */ },
  "preMealBGTrace": [ /* [V2BGReading] — 2h before meal */ ],
  "postMealBGTrace": [ /* [V2BGReading] — meal to +8h */ ],
  "scheduledEntries": [ /* [V2ScheduledEntry] */ ],
  "garminContributions": [ /* [V2GarminContribution] */ ],
  "dosingSummary": { /* V2DosingSummary */ },
  "bolusEvents": [ /* [V2BolusEvent] */ ],
  "tempBasalEvents": [ /* [V2TempBasalEvent] */ ],
  "loopDecisions": [ /* [V2LoopDecision] */ ]
}
```

#### `V2MealOutcome` — Core Meal Record

```json
{
  "id": "UUID",
  "date": "2026-02-12T12:30:00Z",
  "mealID": "UUID-string",

  "carbs": 65.0,
  "fat": 22.0,
  "protein": 18.0,
  "fiber": 4.0,

  "tauCarb": 42.5,
  "proteinFactor": 0.28,
  "fatTotalEquiv": 15.2,
  "upfrontPercent": 0.55,
  "curveSuggestedPercent": 0.55,
  "insulinDemandFactor": 1.12,
  "safeWindowMinutes": 90,

  "garminSnapshot": { /* GarminContextSnapshot or null */ },
  "garminContributions": [ /* [V2GarminContribution] or null */ ],

  "bgAtMeal": 135,
  "carbRatioAtMeal": 8.0,
  "isfAtMeal": 40.0,

  "mealSMBMultiplier": 2.0,
  "mealModeWasActive": true,

  "adaptiveAdjustments": [ /* [AdaptiveAdjustmentRecord] */ ],
  "checkpoints": [ /* [V2BGCheckpoint] */ ],
  "hasConfoundingMeal": false,
  "actualBolusDelivered": 4.5,
  "mealDetectedAt": "2026-02-12T12:15:00Z"
}
```

#### `V2BGReading` — Blood Glucose Point

```json
{
  "date": "2026-02-12T12:30:00Z",
  "glucose": 135,
  "direction": "Flat"
}
```

**Pre-meal trace:** 2 hours before `outcome.date`, every CGM reading (~5 min intervals)
**Post-meal trace:** From `outcome.date` to +8 hours (or now if meal is recent)

Query:
```swift
let request = GlucoseStored.fetchRequest()
request.predicate = NSPredicate(
    format: "date >= %@ AND date <= %@",
    start as NSDate, end as NSDate
)
request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
```

#### `V2BGCheckpoint` — Outcome at Fixed Intervals

BG values at 30-minute checkpoints from 0.5h to 8h post-meal:

```json
{
  "hoursAfterMeal": 1.5,
  "bgValue": 185,
  "isClean": true,
  "curvePhase": "carb"
}
```

Phases: `carb` (0-2h), `protein` (2-5h), `fat` (4-8h), `overlap`, `skip`

#### `V2ScheduledEntry` — Dosing Entries Written to Core Data

```json
{
  "date": "2026-02-12T14:00:00Z",
  "carbEquivalent": 8.5,
  "entryType": "protein-gluco",
  "isAbsorbed": true,
  "isFPU": true
}
```

Entry types: `"carb"`, `"protein-gluco"`, `"fat-resistance"`, `"unknown"`

Query:
```swift
let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
request.predicate = NSPredicate(format: "fpuID == %@", uuid as CVarArg)
```

#### `V2DosingSummary` — What the Engine Decided

```json
{
  "upfrontCarbsForBolus": 35.75,
  "upfrontInsulin": 4.47,
  "proteinGlucoEquivalent": 5.04,
  "fatCarbEquivalent": 15.2,
  "totalEffectiveCarbs": 65.0,
  "totalScheduledEntries": 12,
  "pendingEntries": 3,
  "absorbedEntries": 9
}
```

#### `V2BolusEvent` — Insulin Delivery

```json
{
  "date": "2026-02-12T12:30:00Z",
  "amount": 4.5,
  "isSMB": false,
  "isExternal": false
}
```

Query:
```swift
let request = NSFetchRequest<NSManagedObject>(entityName: "BolusStored")
request.predicate = NSPredicate(
    format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
    start as NSDate, end as NSDate
)
```

#### `V2TempBasalEvent` — Temp Basal Changes

```json
{
  "date": "2026-02-12T12:35:00Z",
  "rate": 3.5,
  "duration": 30
}
```

Query: `NSFetchRequest<NSManagedObject>(entityName: "TempBasalStored")` with same timestamp predicate.

#### `V2LoopDecision` — oref Algorithm State (~5 min intervals)

```json
{
  "date": "2026-02-12T12:35:00Z",
  "glucose": 142,
  "iob": 5.2,
  "cob": 45,
  "eventualBG": 165,
  "insulinReq": 1.2,
  "smbToDeliver": 0.8,
  "tempBasalRate": 3.5,
  "scheduledBasal": 1.0,
  "sensitivityRatio": 1.05,
  "reason": "COB: 45g, Dev: 15, BGI: -3.2, ISF: 40..."
}
```

Note: `reason` is truncated to 200 characters to avoid bloating the export.

Query:
```swift
let request = OrefDetermination.fetchRequest()
request.predicate = NSPredicate(
    format: "deliverAt >= %@ AND deliverAt <= %@",
    start as NSDate, end as NSDate
)
```

#### `V2GarminContribution` — Sensitivity Breakdown

```json
{
  "metric": "Sleep Score",
  "value": "42/100",
  "impact": -0.22,
  "description": "Terrible sleep: 22% more resistant"
}
```

#### `GarminContextSnapshot` — Raw Garmin Data

```json
{
  "queryTime": "2026-02-12T12:00:00Z",
  "restingHeartRateInBeatsPerMinute": 58,
  "averageHeartRateInBeatsPerMinute": 72,
  "averageStressLevel": 35,
  "maxStressLevel": 78,
  "stressDurationInSeconds": 14400,
  "steps": 4200,
  "activeKilocalories": 280,
  "bodyBatteryChargedValue": 45,
  "bodyBatteryDrainedValue": 55,
  "yesterdaySteps": 8500,
  "yesterdayActiveKilocalories": 520,
  "sleepDurationInSeconds": 25200,
  "deepSleepDurationInSeconds": 5400,
  "lightSleepDurationInSeconds": 12600,
  "remSleepInSeconds": 7200,
  "sleepScoreValue": 42,
  "currentBodyBattery": 30,
  "bodyBatteryAtWake": 65,
  "currentStressLevel": 45,
  "lastNightAvg": 38,
  "lastNight5MinHigh": 62,
  "vo2Max": 42.5,
  "fitnessAge": 35,
  "restingHR7DayAvg": 56,
  "hrvWeeklyAvg": 42
}
```

### Data Gathering Flow

`buildComprehensiveExport(context:)` does the following for each of the 90-day meal outcomes:

```
For each V2MealOutcome:
  1. Fetch pre-meal BG trace
     └─ GlucoseStored: (meal.date - 2h) to meal.date

  2. Fetch post-meal BG trace
     └─ GlucoseStored: meal.date to min(meal.date + 8h, now)

  3. Fetch scheduled dosing entries
     └─ CarbEntryStored: WHERE fpuID == outcome.mealID

  4. Get Garmin contributions
     ├─ Use stored contributions if available (preferred)
     └─ Re-derive from stored GarminContextSnapshot (legacy fallback)

  5. Compute dosing summary
     ├─ upfrontCarbs = carbs * upfrontPercent * insulinDemandFactor
     ├─ upfrontInsulin = upfrontCarbs / carbRatioAtMeal
     ├─ proteinGlucoEquiv = protein * proteinFactor
     └─ fatCarbEquiv = outcome.fatTotalEquiv

  6. Fetch bolus events
     └─ BolusStored: WHERE pumpEvent.timestamp in [meal.date, meal.date + 8h]

  7. Fetch temp basal events
     └─ TempBasalStored: WHERE pumpEvent.timestamp in [meal.date, meal.date + 8h]

  8. Fetch loop decisions
     └─ OrefDetermination: WHERE deliverAt in [meal.date, meal.date + 8h]
```

---

## 3. AI Health Data Export (Text/Prompt)

**Source:** `Trio/Sources/Modules/AIInsightsConfig/HealthDataExporter.swift`

This system exports health data as a formatted text prompt for Claude AI analysis. While not JSON, it's a structured data export that includes macros, treatments, and BG.

### Data Structures

#### `ExportedData` — Top-Level Container

```swift
struct ExportedData {
    let glucoseReadings: [GlucoseReading]
    let carbEntries: [CarbEntry]
    let bolusEvents: [BolusEvent]
    let loopStates: [LoopState]
    let settings: SettingsSummary
    let statistics: Statistics
    let multiTimeframeStats: MultiTimeframeStatistics?
    let healthMetrics: HealthMetrics?
}
```

#### `GlucoseReading`

```swift
struct GlucoseReading {
    let date: Date
    let value: Int          // mg/dL
    let direction: String?  // CGM trend arrow
    let isManual: Bool
}
```

Query:
```swift
let request = NSFetchRequest<NSManagedObject>(entityName: "GlucoseStored")
request.predicate = NSPredicate(format: "date >= %@", startDate as NSDate)
request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
```

#### `CarbEntry` — Macros

```swift
struct CarbEntry {
    let date: Date
    let carbs: Double
    let fat: Double
    let protein: Double
    let note: String?
}
```

Note: FPU (fat protein unit) entries are excluded with `isFPU == NO`:
```swift
request.predicate = NSPredicate(format: "date >= %@ AND isFPU == NO", startDate as NSDate)
```

#### `BolusEvent`

```swift
struct BolusEvent {
    let date: Date
    let amount: Decimal
    let isSMB: Bool
    let isExternal: Bool
}
```

#### `LoopState` — Algorithm Snapshot (~5 min)

```swift
struct LoopState {
    let date: Date
    let glucose: Decimal
    let iob: Decimal
    let cob: Int
    let tempBasalRate: Decimal
    let scheduledBasalRate: Decimal
    let smbDelivered: Decimal
    let eventualBG: Decimal?
    let insulinReq: Decimal
    let reason: String?
}
```

#### `SettingsSummary`

```swift
struct SettingsSummary {
    let units: String               // "mg/dL" or "mmol/L"
    let targetLow: Int
    let targetHigh: Int
    let maxIOB: Decimal
    let maxBolus: Decimal
    let dia: Decimal
    let carbRatioSchedule: [(time: String, ratio: Decimal)]
    let isfSchedule: [(time: String, sensitivity: Decimal)]
    let basalSchedule: [(time: String, rate: Decimal)]
    let targetSchedule: [(time: String, low: Decimal, high: Decimal)]
}
```

#### `Statistics` — Computed Glycemic Stats

```swift
struct Statistics {
    let averageGlucose: Int
    let standardDeviation: Double
    let coefficientOfVariation: Double    // SD / Mean * 100
    let gmi: Double                       // 3.31 + 0.02392 * meanGlucose
    let minGlucose: Int
    let maxGlucose: Int
    let timeInRange: Double               // % between targetLow-targetHigh
    let timeBelowRange: Double            // % below targetLow (includes <54)
    let timeAboveRange: Double            // % above targetHigh (includes >250)
    let timeVeryLow: Double               // % below 54
    let timeVeryHigh: Double              // % above 250
    let totalCarbs: Double
    let totalBolus: Decimal
    let totalBasal: Decimal               // Estimated: sum(tempBasalRate * 5min/60)
    let readingCount: Int
    let daysOfData: Int
}
```

#### `MultiTimeframeStatistics`

Computed for 1, 3, 7, 14, 30, and 90-day periods. Each period includes:

```swift
struct TimeframeStat {
    let days: Int
    let averageGlucose: Int
    let standardDeviation: Double
    let coefficientOfVariation: Double
    let gmi: Double
    let timeInRange: Double
    let timeBelowRange: Double
    let timeAboveRange: Double
    let timeVeryLow: Double
    let timeVeryHigh: Double
    let readingCount: Int
}
```

#### `HealthMetrics` — Apple Health Wearable Data

```swift
struct HealthMetrics {
    let dailyActivity: [DailyActivitySummary]   // steps, calories, exercise min
    let sleepSummaries: [SleepSummary]           // duration, efficiency, deep/REM
    let hrvData: [HRVDataPoint]                  // SDNN per day
    let heartRateStats: HeartRateStats?          // resting, avg, min, max
    let workouts: [WorkoutSummary]               // type, duration, calories, HR
}
```

Each sub-type:

```swift
struct DailyActivitySummary {
    let date: Date
    let steps: Int
    let activeCalories: Double
    let exerciseMinutes: Int
}

struct SleepSummary {
    let date: Date
    let bedtime: Date
    let wakeTime: Date
    let hoursAsleep: Double
    let sleepEfficiency: Double
    let deepSleepHours: Double?
    let remSleepHours: Double?
}

struct HRVDataPoint {
    let date: Date
    let averageSDNN: Double
    let minSDNN: Double
    let maxSDNN: Double
}

struct HeartRateStats {
    let averageRestingHR: Int
    let minHR: Int
    let maxHR: Int
    let averageHR: Int
}

struct WorkoutSummary {
    let date: Date
    let type: String
    let durationMinutes: Int
    let calories: Double?
    let averageHeartRate: Int?
}
```

### Analysis Types & Output Formats

The `formatForPrompt()` method produces different text layouts depending on the analysis type:

| Type | Period | BG Data | Carb Detail | Bolus Detail | Loop Data | Health Metrics |
|------|--------|---------|-------------|--------------|-----------|----------------|
| **Quick** | 1-7 days | Sampled at 15 min | All entries | Grouped by type | 15 min intervals | Optional |
| **Weekly Report** | 7 days | 15 min intervals | All entries | Grouped by type | 15 min intervals | No |
| **Chat** | 7 days | 6h recent context | No | No | 10 min, last 6h | Optional |
| **Doctor Visit** | 30 days | 5 min intervals | All entries | Grouped by type | 5 min intervals | Optional |
| **Why High/Low** | 4 hours | Every reading | All + Cronometer | All | Sampled every 3rd | Optional |
| **Claude-o-Tune** | 30 days | 15 min intervals | All entries | Grouped by type | 15 min intervals | Optional |

### Carb Entry Formatting (with macros)

```
Format: "MM/dd HH:mm | Xg (F:Yg P:Zg) "note""

Example output:
02/12 12:30 | 65g (F:22g P:18g) "Lunch - chicken sandwich"
02/12 15:00 | 15g
02/12 18:45 | 80g (F:35g P:25g) "Dinner - pasta with meat sauce"
```

### Loop State Formatting

```
Format: "DateTime | BG | IOB | COB | TempBasal | SMB"

Example output:
02/12 12:30 | 135 | 2.50 | 45 | 3.20 | 0.80
02/12 12:45 | 142 | 3.10 | 38 | 2.80 | -
02/12 13:00 | 155 | 2.90 | 30 | 2.50 | 0.50
```

### Bolus Formatting

Grouped by type:

```
Manual Boluses:
02/12 12:30 | 4.50 U
02/12 18:45 | 6.00 U

SMBs: 42 deliveries, 8.50 U total

External/Pen Injections:
02/12 08:00 | 2.00 U
```

### Why High/Low — Cronometer Meal Comparison

The "Why High/Low" analysis type includes Cronometer-detected meals alongside Trio carb entries for comparison:

```
🍽️ TRIO CARB ENTRIES (what user entered for dosing)
02/12 12:30: 45g carbs (F:10g P:8g)

📱 ACTUAL MEALS FROM CRONOMETER (via Apple Health, last 12 hours)
~02/12 12:15: 65g carbs | 22g fat | 18g protein | 470 kcal (C:55% F:42% P:15%)
TOTALS: 65g carbs | 22g fat | 18g protein | 470 kcal

🔬 MEAL DOSING ANALYSIS (simulation vs actual)
--- Meal at ~02/12 12:15 ---
• Cronometer actual: 65g C | 22g F | 18g P
• Trio entered: 45g carbs (missed 20g = 31% under-counted)
• Bolus given: 4.50U
• Bolus needed for actual carbs: 8.1U (at current CR 1:8)
• Fat/Protein Units (FPU): 22g fat + 18g protein = 15g carb-equivalents over 4.5h
```

### Data Gathering Flow

```swift
func exportData(days: Int, ...) async throws -> ExportedData {
    let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

    // Parallel Core Data queries
    let glucoseReadings = try await fetchGlucoseReadings(since: startDate)  // GlucoseStored
    let carbEntries = try await fetchCarbEntries(since: startDate)          // CarbEntryStored (isFPU == NO)
    let bolusEvents = try await fetchBolusEvents(since: startDate)          // BolusStored via pumpEvent
    let loopStates = try await fetchLoopStates(since: startDate)            // OrefDetermination

    // Computed statistics
    let statistics = calculateStatistics(glucose:carbs:boluses:loopStates:...)
    let multiStats = days >= 7 ? calculateMultiTimeframeStats(...) : nil

    // Optional Apple Health metrics
    let healthMetrics = await fetchHealthMetrics(days:settings:)

    return ExportedData(...)
}
```

---

## 4. Core Data Entities Used

Both export systems query the same Core Data store. Here are the entities and the fields each export reads:

### `GlucoseStored`

| Field | Type | Used By |
|-------|------|---------|
| `date` | Date | Both |
| `glucose` | Int16 | Both (as mg/dL Int) |
| `direction` | String? | Both (CGM trend arrow) |
| `isManual` | Bool | AI export only |

### `CarbEntryStored`

| Field | Type | Used By |
|-------|------|---------|
| `date` | Date | Both |
| `carbs` | Double | Both |
| `fat` | Double | Both |
| `protein` | Double | Both |
| `note` | String? | AI export |
| `isFPU` | Bool | Filter: `isFPU == NO` for AI export; `fpuID` match for V2 export |
| `fpuID` | UUID? | V2 export: matches against `outcome.mealID` |

### `BolusStored` (via `pumpEvent` relationship)

| Field | Type | Used By |
|-------|------|---------|
| `pumpEvent.timestamp` | Date | Both |
| `amount` | NSDecimalNumber | Both |
| `isSMB` | Bool | Both |
| `isExternal` | Bool | Both |

### `TempBasalStored` (via `pumpEvent` relationship)

| Field | Type | Used By |
|-------|------|---------|
| `pumpEvent.timestamp` | Date | V2 export |
| `rate` | NSDecimalNumber | V2 export |
| `duration` | Int16 | V2 export |

### `OrefDetermination`

| Field | Type | Used By |
|-------|------|---------|
| `deliverAt` | Date | Both |
| `glucose` | NSDecimalNumber | Both |
| `iob` | NSDecimalNumber | Both |
| `cob` | Int16 | Both |
| `rate` | NSDecimalNumber | Both (temp basal rate) |
| `scheduledBasal` | NSDecimalNumber | Both |
| `smbToDeliver` | NSDecimalNumber | Both |
| `eventualBG` | NSDecimalNumber | Both |
| `insulinReq` | NSDecimalNumber | Both |
| `sensitivityRatio` | NSDecimalNumber | V2 export |
| `reason` | String? | Both (truncated to 200 chars in V2) |

### `V2MealOutcomeStored` (V2 export only)

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `date` | Date | Dose time |
| `mealID` | String | Links to `CarbEntryStored.fpuID` |
| `carbs`, `fat`, `protein`, `fiber` | Double | Original meal macros |
| `tauCarb`, `proteinFactor`, `fatTotalEquiv` | Double | Curve parameters |
| `upfrontPercent`, `curveSuggestedPercent` | Double | Split dosing percentages |
| `insulinDemandFactor` | Double | Garmin-derived |
| `safeWindowMinutes` | Int16 | |
| `bgAtMeal` | Int16 | |
| `carbRatioAtMeal`, `isfAtMeal` | Double | Settings at dose time |
| `mealSMBMultiplier` | Double | |
| `mealModeWasActive` | Bool | |
| `hasConfoundingMeal` | Bool | |
| `actualBolusDelivered` | Double | |
| `mealDetectedAt` | Date? | |
| `checkpointsJSON` | Data? | JSON-encoded `[V2BGCheckpoint]` |
| `adaptiveAdjustmentsJSON` | Data? | JSON-encoded `[AdaptiveAdjustmentRecord]` |
| `garminSnapshotJSON` | Data? | JSON-encoded `GarminContextSnapshot` |
| `garminContributionsJSON` | Data? | JSON-encoded `[V2GarminContribution]` |

---

## 5. File Inventory

### V2 Comprehensive Export

| File | Purpose |
|------|---------|
| `Trio/Sources/Services/V2CurveOutcomeLearning.swift` | `buildComprehensiveExport()`, all export types, Core Data queries |
| `Trio/Sources/Modules/Settings/View/Subviews/V2OutcomeAnalysisView.swift` | Export button UI, JSON encoding, share sheet |

### AI Health Data Export

| File | Purpose |
|------|---------|
| `Trio/Sources/Modules/AIInsightsConfig/HealthDataExporter.swift` | `exportData()`, `formatForPrompt()`, all analysis type formatters, statistics calculation |

### Shared Core Data

| File | Purpose |
|------|---------|
| `Trio/Sources/Models/CoreData/Trio.xcdatamodeld` | Entity definitions |
| `Trio/Sources/Models/CoreData/CoreDataStack.swift` | Managed object context creation |

---

## Summary

The two export systems serve different purposes but draw from the same Core Data:

**V2 Meal Export** produces a machine-readable JSON file with per-meal granularity — every CGM reading, bolus, temp basal, and loop decision in the 2h-before to 8h-after window around each meal. Intended for offline analysis or sharing.

**AI Health Data Export** produces a text-formatted prompt with period-level aggregation — sampled loop states, grouped boluses, and computed statistics across configurable time windows (1-90 days). Intended for direct Claude API analysis.

Both include the full macro breakdown (carbs, fat, protein, fiber) for every carb entry, complete BG traces, all insulin delivery events, and the settings that were active at the time.

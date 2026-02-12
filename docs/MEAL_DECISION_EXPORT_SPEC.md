# Meal Decision Export — Specification

A focused export that captures everything about a dosing decision and its outcome: the meal macros selected, what the calculator recommended, what was actually delivered, and the full BG + insulin trace for 6-8 hours afterward. Designed for tuning the system by reviewing real meal outcomes.

---

## Table of Contents

1. [What Gets Captured](#1-what-gets-captured)
2. [JSON Schema](#2-json-schema)
3. [When to Capture Each Piece](#3-when-to-capture-each-piece)
4. [Core Data Queries for Post-Meal Trace](#4-core-data-queries-for-post-meal-trace)
5. [Implementation Plan](#5-implementation-plan)
6. [Example Export](#6-example-export)

---

## 1. What Gets Captured

Each export record represents **one dosing decision** and its 6-8h outcome:

### At Dose Time (captured immediately)

| Category | Fields | Source |
|----------|--------|--------|
| **Selected Meals** | Per-meal: date, label, carbs, fat, protein, fiber, source | `V2DetectedMeal` selections |
| **Combined Macros** | Total carbs, fat, protein, fiber entered for dosing | Sum of selected meals |
| **BG at Dose** | Current glucose, 15-min delta, trend direction | `GlucoseStored` (latest) |
| **Pump Settings** | ISF, carb ratio, target, basal rate, max bolus, max IOB | `SettingsManager` schedules |
| **Algorithm State** | IOB, COB, eventual BG, min predicted BG, sensitivity ratio | `OrefDetermination` (latest) |
| **Calculator Breakdown** | Target diff insulin, COB insulin, IOB reduction, trend insulin, whole calc, factored insulin, final recommended | `CalculationResult` |
| **Dose Modifiers** | Fatty meal correction on/off, super bolus on/off, fraction | User toggles + settings |
| **Recommended Dose** | `insulinCalculated` (the number shown to user) | `CalculationResult` |
| **User's Actual Dose** | Amount user confirmed (may differ if they adjusted) | `state.insulinDelivered` |
| **External Insulin** | Whether dose was pen injection vs pump | `state.externalInsulin` |
| **Dose Timestamp** | When the bolus was confirmed | `Date()` at confirm |

### Post-Meal (captured via background queries at export time)

| Category | Fields | Source |
|----------|--------|--------|
| **BG Trace** | Every CGM reading from dose time to +8h | `GlucoseStored` |
| **SMBs Delivered** | All automatic micro-boluses with timestamps | `BolusStored` where `isSMB == true` |
| **Manual Follow-up Boluses** | Any additional user boluses | `BolusStored` where `isSMB == false` |
| **Temp Basals** | All temp basal rate changes | `TempBasalStored` |
| **Loop Decisions** | oref state every ~5 min (IOB, COB, eventual BG, insulin req) | `OrefDetermination` |

---

## 2. JSON Schema

### Root: `MealDecisionExport`

```json
{
  "exportDate": "2026-02-12T20:00:00Z",
  "appVersion": "1.2.3",
  "records": [ /* [MealDecisionRecord] */ ]
}
```

### `MealDecisionRecord` — One Per Dosing Event

```json
{
  "id": "UUID",
  "doseTimestamp": "2026-02-12T12:30:00Z",

  "selectedMeals": [
    {
      "date": "2026-02-12T12:15:00Z",
      "label": "Lunch",
      "carbs": 45.0,
      "fat": 18.0,
      "protein": 22.0,
      "fiber": 4.0,
      "source": "Cronometer"
    }
  ],

  "combinedMacros": {
    "carbs": 45.0,
    "fat": 18.0,
    "protein": 22.0,
    "fiber": 4.0,
    "estimatedCalories": 430
  },

  "bgAtDose": {
    "glucose": 135,
    "delta15min": 8,
    "direction": "FortyFiveUp",
    "timestamp": "2026-02-12T12:28:00Z"
  },

  "algorithmState": {
    "iob": 1.25,
    "cob": 12,
    "eventualBG": 142,
    "minPredBG": 95,
    "sensitivityRatio": 1.0
  },

  "pumpSettings": {
    "isf": 40.0,
    "carbRatio": 8.0,
    "target": 100.0,
    "basalRate": 1.0,
    "maxBolus": 10.0,
    "maxIOB": 8.0
  },

  "calculatorBreakdown": {
    "targetDifference": 35.0,
    "targetDifferenceInsulin": 0.875,
    "carbInsulin": 5.625,
    "iobReduction": -1.25,
    "trendInsulin": 0.20,
    "wholeCalc": 5.45,
    "factoredInsulin": 5.45,
    "recommended": 5.4,
    "fattyMealEnabled": false,
    "superBolusEnabled": false,
    "fraction": 1.0
  },

  "delivery": {
    "recommended": 5.4,
    "userConfirmed": 5.0,
    "isExternal": false,
    "note": "Chicken sandwich with fries"
  },

  "postMealTrace": {
    "windowHours": 8,
    "bgReadings": [
      { "minutesAfterDose": 0, "glucose": 135, "direction": "FortyFiveUp" },
      { "minutesAfterDose": 5, "glucose": 138, "direction": "FortyFiveUp" },
      { "minutesAfterDose": 10, "glucose": 142, "direction": "SingleUp" },
      ...
      { "minutesAfterDose": 480, "glucose": 112, "direction": "Flat" }
    ],
    "peakBG": { "minutesAfterDose": 55, "glucose": 195 },
    "nadirBG": { "minutesAfterDose": 180, "glucose": 88 },
    "bgAt2h": 155,
    "bgAt4h": 108,
    "bgAt6h": 112,
    "bgAt8h": 112
  },

  "insulinDelivery": {
    "initialBolus": 5.0,
    "smbsDelivered": [
      { "minutesAfterDose": 15, "amount": 0.8 },
      { "minutesAfterDose": 20, "amount": 0.5 },
      { "minutesAfterDose": 30, "amount": 0.3 }
    ],
    "followUpBoluses": [],
    "totalSMBInsulin": 1.6,
    "totalManualInsulin": 5.0,
    "totalInsulinDelivered": 6.6,
    "tempBasals": [
      { "minutesAfterDose": 5, "rate": 3.5, "durationMinutes": 30 },
      { "minutesAfterDose": 35, "rate": 2.0, "durationMinutes": 30 },
      { "minutesAfterDose": 120, "rate": 0.0, "durationMinutes": 30 }
    ]
  },

  "loopDecisions": [
    {
      "minutesAfterDose": 5,
      "glucose": 138,
      "iob": 6.2,
      "cob": 45,
      "eventualBG": 165,
      "insulinReq": 1.2,
      "smbDelivered": 0.8,
      "tempBasalRate": 3.5,
      "sensitivityRatio": 1.0
    },
    ...
  ]
}
```

### Summary Statistics (computed at export time)

Included in each record for quick scanning:

```json
{
  "summary": {
    "carbsEntered": 45,
    "recommendedDose": 5.4,
    "userDose": 5.0,
    "totalInsulinDelivered": 6.6,
    "insulinPerCarb": 0.147,
    "bgAtDose": 135,
    "peakBG": 195,
    "peakMinutes": 55,
    "nadirBG": 88,
    "nadirMinutes": 180,
    "bgAt2h": 155,
    "bgAt4h": 108,
    "timeAbove180Minutes": 25,
    "timeBelow70Minutes": 0,
    "returnToRangeMinutes": 90
  }
}
```

---

## 3. When to Capture Each Piece

### Phase 1: At Dose Confirmation

When user taps "Confirm" in the treatment view, capture a snapshot of everything the calculator used:

```swift
struct MealDecisionSnapshot {
    let id: UUID
    let doseTimestamp: Date

    // Selected meals (preserve originals for macro breakdown)
    let selectedMeals: [V2DetectedMeal]

    // Combined macros
    let totalCarbs: Double
    let totalFat: Double
    let totalProtein: Double
    let totalFiber: Double

    // BG state
    let currentBG: Int
    let deltaBG: Decimal
    let bgDirection: String?

    // Algorithm state (from latest OrefDetermination)
    let iob: Decimal
    let cob: Int
    let eventualBG: Decimal?
    let minPredBG: Decimal?
    let sensitivityRatio: Decimal?

    // Settings at dose time
    let isf: Decimal
    let carbRatio: Decimal
    let target: Decimal
    let basalRate: Decimal
    let maxBolus: Decimal
    let maxIOB: Decimal

    // Calculator result
    let calculationResult: CalculationResult
    let fattyMealEnabled: Bool
    let superBolusEnabled: Bool
    let fraction: Decimal

    // What happened
    let recommendedDose: Decimal
    let userConfirmedDose: Decimal
    let isExternalInsulin: Bool
    let note: String?
}
```

**Where to capture:** In `invokeTreatmentsTask()`, right before `saveMeal()` is called. All values are available on the state model at this point.

**Storage:** Persist to `~/Documents/meal_decision_log.json` (append-only, with date-based pruning).

### Phase 2: Post-Meal Trace (at export time)

When the user triggers an export (or automatically after 8h), query Core Data for the post-meal window:

```
For each snapshot where doseTimestamp + 8h < now:
  1. BG trace:     GlucoseStored WHERE date IN [doseTimestamp, doseTimestamp + 8h]
  2. Boluses:      BolusStored WHERE pumpEvent.timestamp IN [doseTimestamp, doseTimestamp + 8h]
  3. Temp basals:  TempBasalStored WHERE pumpEvent.timestamp IN [doseTimestamp, doseTimestamp + 8h]
  4. Loop states:  OrefDetermination WHERE deliverAt IN [doseTimestamp, doseTimestamp + 8h]
```

---

## 4. Core Data Queries for Post-Meal Trace

### BG Trace

```swift
func fetchBGTrace(from start: Date, to end: Date, context: NSManagedObjectContext) async -> [BGPoint] {
    await context.perform {
        let request = GlucoseStored.fetchRequest()
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            start as NSDate, end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

        guard let results = try? context.fetch(request) else { return [] }
        return results.compactMap { entry in
            guard let date = entry.date else { return nil }
            return BGPoint(
                minutesAfterDose: date.timeIntervalSince(start) / 60,
                glucose: Int(entry.glucose),
                direction: entry.direction
            )
        }
    }
}
```

### Boluses (SMBs + Manual)

```swift
func fetchBoluses(from start: Date, to end: Date, context: NSManagedObjectContext) async -> [BolusPoint] {
    await context.perform {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BolusStored")
        request.predicate = NSPredicate(
            format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
            start as NSDate, end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "pumpEvent.timestamp", ascending: true)]

        guard let results = try? context.fetch(request) else { return [] }
        return results.compactMap { bolus in
            guard let pe = bolus.value(forKey: "pumpEvent") as? NSManagedObject,
                  let ts = pe.value(forKey: "timestamp") as? Date
            else { return nil }

            let amount = (bolus.value(forKey: "amount") as? NSDecimalNumber)?.doubleValue ?? 0
            guard amount > 0 else { return nil }

            return BolusPoint(
                minutesAfterDose: ts.timeIntervalSince(start) / 60,
                amount: amount,
                isSMB: bolus.value(forKey: "isSMB") as? Bool ?? false,
                isExternal: bolus.value(forKey: "isExternal") as? Bool ?? false
            )
        }
    }
}
```

### Temp Basals

```swift
func fetchTempBasals(from start: Date, to end: Date, context: NSManagedObjectContext) async -> [TempBasalPoint] {
    await context.perform {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TempBasalStored")
        request.predicate = NSPredicate(
            format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
            start as NSDate, end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "pumpEvent.timestamp", ascending: true)]

        guard let results = try? context.fetch(request) else { return [] }
        return results.compactMap { tb in
            guard let pe = tb.value(forKey: "pumpEvent") as? NSManagedObject,
                  let ts = pe.value(forKey: "timestamp") as? Date
            else { return nil }

            return TempBasalPoint(
                minutesAfterDose: ts.timeIntervalSince(start) / 60,
                rate: (tb.value(forKey: "rate") as? NSDecimalNumber)?.doubleValue ?? 0,
                durationMinutes: Int((tb.value(forKey: "duration") as? Int16) ?? 0)
            )
        }
    }
}
```

### Loop Decisions (sampled)

```swift
func fetchLoopDecisions(from start: Date, to end: Date, context: NSManagedObjectContext) async -> [LoopDecisionPoint] {
    await context.perform {
        let request = OrefDetermination.fetchRequest()
        request.predicate = NSPredicate(
            format: "deliverAt >= %@ AND deliverAt <= %@",
            start as NSDate, end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "deliverAt", ascending: true)]

        guard let results = try? context.fetch(request) else { return [] }
        return results.compactMap { det in
            guard let date = det.deliverAt else { return nil }
            return LoopDecisionPoint(
                minutesAfterDose: date.timeIntervalSince(start) / 60,
                glucose: Int((det.glucose ?? 0).doubleValue),
                iob: (det.iob ?? 0).doubleValue,
                cob: Int(det.cob),
                eventualBG: Int((det.eventualBG ?? 0).doubleValue),
                insulinReq: (det.insulinReq ?? 0).doubleValue,
                smbDelivered: (det.smbToDeliver ?? 0).doubleValue,
                tempBasalRate: det.rate?.doubleValue,
                sensitivityRatio: (det.sensitivityRatio ?? 1).doubleValue
            )
        }
    }
}
```

---

## 5. Implementation Plan

### New Files Needed

| File | Purpose |
|------|---------|
| `Trio/Sources/Models/MealDecisionLog.swift` | `MealDecisionSnapshot` struct + `MealDecisionRecord` (full record with post-meal data) + `MealDecisionExport` (root) |
| `Trio/Sources/Services/MealDecisionLogger.swift` | Singleton that saves snapshots, builds full export records, queries post-meal data |
| `Trio/Sources/Modules/Settings/View/Subviews/MealDecisionExportView.swift` | Export UI — list of recent decisions, "Export All" button, share sheet |

### Integration Points

**1. Capture snapshot at dose time** — in `TreatmentsStateModel.invokeTreatmentsTask()`:

```swift
// Right before saveMeal(), capture the decision snapshot
let snapshot = MealDecisionSnapshot(
    id: UUID(),
    doseTimestamp: Date(),
    selectedMeals: v2SelectedMealsForChart ?? [],
    totalCarbs: Double(truncating: carbs as NSDecimalNumber),
    totalFat: Double(truncating: fat as NSDecimalNumber),
    totalProtein: Double(truncating: protein as NSDecimalNumber),
    totalFiber: Double(truncating: fiber as NSDecimalNumber),
    currentBG: /* from latest glucose */,
    deltaBG: /* from calculation input */,
    // ... all other fields from state + calculation result
    recommendedDose: insulinCalculated,
    userConfirmedDose: /* amount user actually confirmed */,
    isExternalInsulin: externalInsulin,
    note: note
)
MealDecisionLogger.shared.saveSnapshot(snapshot)
```

**2. Record dose timestamp** (for meal grouping in snapshot store):

```swift
NutritionSnapshotStore.shared.recordDoseTimestamp()
```

**3. Export with post-meal data** — when user opens export view:

```swift
let export = await MealDecisionLogger.shared.buildExport(
    context: CoreDataStack.shared.newTaskContext()
)
// Encode as JSON, present share sheet
```

### Storage

- **Snapshots:** `~/Documents/meal_decision_snapshots.json` — append-only, 90-day retention
- **Full export:** Temp directory, `meal-decisions-{date}.json`
- **Encoding:** `JSONEncoder` with `.iso8601` date strategy, `.prettyPrinted`, `.sortedKeys`

### Export Trigger Options

1. **Manual:** Button in Settings > "Meal Decision Log" > "Export All"
2. **Automatic:** Could optionally auto-export when a meal's 8h window completes (background task)
3. **Per-meal:** Tap a specific meal record to export just that one

---

## 6. Example Export

A complete example of what one record looks like in the exported JSON:

```json
{
  "exportDate": "2026-02-12T20:30:00Z",
  "appVersion": "1.2.3",
  "records": [
    {
      "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
      "doseTimestamp": "2026-02-12T12:30:00Z",

      "selectedMeals": [
        {
          "date": "2026-02-12T12:15:03Z",
          "label": "Lunch",
          "carbs": 65.0,
          "fat": 22.0,
          "protein": 18.0,
          "fiber": 4.0,
          "source": "Cronometer"
        }
      ],

      "combinedMacros": {
        "carbs": 65.0,
        "fat": 22.0,
        "protein": 18.0,
        "fiber": 4.0,
        "estimatedCalories": 530
      },

      "bgAtDose": {
        "glucose": 135,
        "delta15min": 8,
        "direction": "FortyFiveUp",
        "timestamp": "2026-02-12T12:28:00Z"
      },

      "algorithmState": {
        "iob": 0.45,
        "cob": 0,
        "eventualBG": 142,
        "minPredBG": 110,
        "sensitivityRatio": 1.0
      },

      "pumpSettings": {
        "isf": 40.0,
        "carbRatio": 8.0,
        "target": 100.0,
        "basalRate": 1.0,
        "maxBolus": 10.0,
        "maxIOB": 8.0
      },

      "calculatorBreakdown": {
        "targetDifference": 35,
        "targetDifferenceInsulin": 0.875,
        "carbInsulin": 8.125,
        "iobReduction": -0.45,
        "trendInsulin": 0.20,
        "wholeCalc": 8.75,
        "factoredInsulin": 8.75,
        "recommended": 7.55,
        "fattyMealEnabled": false,
        "superBolusEnabled": false,
        "fraction": 1.0
      },

      "delivery": {
        "recommended": 7.55,
        "userConfirmed": 7.5,
        "isExternal": false,
        "note": "Grilled chicken wrap, fries, diet coke"
      },

      "postMealTrace": {
        "windowHours": 8,
        "bgReadings": [
          { "minutesAfterDose": 0, "glucose": 135, "direction": "FortyFiveUp" },
          { "minutesAfterDose": 5, "glucose": 140, "direction": "SingleUp" },
          { "minutesAfterDose": 10, "glucose": 148, "direction": "SingleUp" },
          { "minutesAfterDose": 15, "glucose": 155, "direction": "SingleUp" },
          { "minutesAfterDose": 20, "glucose": 160, "direction": "FortyFiveUp" },
          { "minutesAfterDose": 25, "glucose": 162, "direction": "Flat" },
          { "minutesAfterDose": 30, "glucose": 165, "direction": "FortyFiveUp" },
          { "minutesAfterDose": 40, "glucose": 172, "direction": "FortyFiveUp" },
          { "minutesAfterDose": 50, "glucose": 178, "direction": "FortyFiveUp" },
          { "minutesAfterDose": 60, "glucose": 182, "direction": "Flat" },
          { "minutesAfterDose": 75, "glucose": 175, "direction": "FortyFiveDown" },
          { "minutesAfterDose": 90, "glucose": 160, "direction": "SingleDown" },
          { "minutesAfterDose": 120, "glucose": 135, "direction": "FortyFiveDown" },
          { "minutesAfterDose": 150, "glucose": 118, "direction": "FortyFiveDown" },
          { "minutesAfterDose": 180, "glucose": 105, "direction": "Flat" },
          { "minutesAfterDose": 210, "glucose": 108, "direction": "Flat" },
          { "minutesAfterDose": 240, "glucose": 115, "direction": "FortyFiveUp" },
          { "minutesAfterDose": 300, "glucose": 125, "direction": "Flat" },
          { "minutesAfterDose": 360, "glucose": 118, "direction": "Flat" },
          { "minutesAfterDose": 420, "glucose": 110, "direction": "Flat" },
          { "minutesAfterDose": 480, "glucose": 108, "direction": "Flat" }
        ],
        "peakBG": { "minutesAfterDose": 60, "glucose": 182 },
        "nadirBG": { "minutesAfterDose": 180, "glucose": 105 },
        "bgAt2h": 135,
        "bgAt4h": 115,
        "bgAt6h": 118,
        "bgAt8h": 108
      },

      "insulinDelivery": {
        "initialBolus": 7.5,
        "smbsDelivered": [
          { "minutesAfterDose": 18, "amount": 0.5 },
          { "minutesAfterDose": 23, "amount": 0.3 },
          { "minutesAfterDose": 33, "amount": 0.5 },
          { "minutesAfterDose": 48, "amount": 0.3 }
        ],
        "followUpBoluses": [],
        "totalSMBInsulin": 1.6,
        "totalManualInsulin": 7.5,
        "totalInsulinDelivered": 9.1,
        "tempBasals": [
          { "minutesAfterDose": 5, "rate": 4.0, "durationMinutes": 30 },
          { "minutesAfterDose": 35, "rate": 3.0, "durationMinutes": 30 },
          { "minutesAfterDose": 65, "rate": 1.5, "durationMinutes": 30 },
          { "minutesAfterDose": 95, "rate": 0.0, "durationMinutes": 30 },
          { "minutesAfterDose": 125, "rate": 0.0, "durationMinutes": 30 },
          { "minutesAfterDose": 155, "rate": 0.5, "durationMinutes": 30 },
          { "minutesAfterDose": 185, "rate": 1.0, "durationMinutes": 30 }
        ]
      },

      "loopDecisions": [
        { "minutesAfterDose": 5, "glucose": 140, "iob": 7.8, "cob": 65, "eventualBG": 85, "insulinReq": 0.5, "smbDelivered": 0.5, "tempBasalRate": 4.0, "sensitivityRatio": 1.0 },
        { "minutesAfterDose": 10, "glucose": 148, "iob": 8.1, "cob": 60, "eventualBG": 90, "insulinReq": 0.3, "smbDelivered": 0.3, "tempBasalRate": 4.0, "sensitivityRatio": 1.0 },
        { "minutesAfterDose": 30, "glucose": 165, "iob": 7.5, "cob": 48, "eventualBG": 95, "insulinReq": 0.5, "smbDelivered": 0.5, "tempBasalRate": 3.0, "sensitivityRatio": 1.0 },
        { "minutesAfterDose": 60, "glucose": 182, "iob": 6.2, "cob": 30, "eventualBG": 110, "insulinReq": 0.0, "smbDelivered": 0.0, "tempBasalRate": 1.5, "sensitivityRatio": 1.0 },
        { "minutesAfterDose": 120, "glucose": 135, "iob": 3.8, "cob": 10, "eventualBG": 95, "insulinReq": 0.0, "smbDelivered": 0.0, "tempBasalRate": 0.0, "sensitivityRatio": 1.0 },
        { "minutesAfterDose": 180, "glucose": 105, "iob": 2.0, "cob": 0, "eventualBG": 85, "insulinReq": 0.0, "smbDelivered": 0.0, "tempBasalRate": 0.5, "sensitivityRatio": 1.0 },
        { "minutesAfterDose": 240, "glucose": 115, "iob": 0.8, "cob": 0, "eventualBG": 108, "insulinReq": 0.0, "smbDelivered": 0.0, "tempBasalRate": 1.0, "sensitivityRatio": 1.0 }
      ],

      "summary": {
        "carbsEntered": 65,
        "recommendedDose": 7.55,
        "userDose": 7.5,
        "totalInsulinDelivered": 9.1,
        "insulinPerCarb": 0.14,
        "bgAtDose": 135,
        "peakBG": 182,
        "peakMinutes": 60,
        "nadirBG": 105,
        "nadirMinutes": 180,
        "bgAt2h": 135,
        "bgAt4h": 115,
        "timeAbove180Minutes": 5,
        "timeBelow70Minutes": 0,
        "returnToRangeMinutes": 75
      }
    }
  ]
}
```

### What This Tells You at a Glance

From the summary of the example meal above:

- **65g carbs** with 22g fat, 18g protein
- Calculator said **7.55U**, user took **7.5U**
- Loop added **1.6U** of SMBs on top, total **9.1U** delivered
- Effective ratio: **0.14 U/g** (9.1U / 65g)
- BG peaked at **182** at 60 min (barely over range, brief spike)
- Dropped to **105** at 3h (good, no low)
- Only **5 min** above 180, **0 min** below 70
- Back in range by **75 min** after dose

With 20-30 of these records you can spot patterns: Are you consistently under-dosing high-fat meals? Do protein-heavy meals cause a late rise at 3-4h? Are your SMBs aggressive enough or too aggressive? Is ISF too strong overnight?

---

## Summary

**Three files to create:**
1. `MealDecisionLog.swift` — all the Codable structs
2. `MealDecisionLogger.swift` — singleton: save snapshot at dose time, build export with post-meal queries
3. `MealDecisionExportView.swift` — settings page with list of records + export button

**Two integration points:**
1. `invokeTreatmentsTask()` — capture snapshot before `saveMeal()`
2. Export view — query Core Data for 6-8h post-meal traces, encode as JSON, share

**Storage:** Simple JSON file in Documents directory, append-only, 90-day retention. No Core Data entity needed for the snapshots themselves.

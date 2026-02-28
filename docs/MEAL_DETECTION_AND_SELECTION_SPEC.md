# Meal Detection & Selection System — Technical Specification

This document describes the meal detection and selection system. The goal is to detect meals logged in external nutrition apps (e.g. Cronometer) via Apple HealthKit and present them in the Trio treatment flow, where selected meal carbs feed into the standard oref bolus calculator.

---

## Table of Contents

1. [Overview & Data Flow](#1-overview--data-flow)
2. [Data Models](#2-data-models)
3. [HealthKit Nutrition Observer](#3-healthkit-nutrition-observer)
4. [Meal Grouping Algorithm](#4-meal-grouping-algorithm)
5. [Meal Loading in the State Model](#5-meal-loading-in-the-state-model)
6. [UI: Meal Feed & Selection](#6-ui-meal-feed--selection)
7. [UI: Meal Card](#7-ui-meal-card)
8. [UI: Manual Meal Entry](#8-ui-manual-meal-entry)
9. [Integration Point: Feeding Carbs into oref](#9-integration-point-feeding-carbs-into-oref)
10. [Settings & Permissions](#10-settings--permissions)
11. [File Inventory](#11-file-inventory)

---

## 1. Overview & Data Flow

```
User logs food in Cronometer (or other Apple Health writer)
    |
    v
Cronometer writes nutrition samples to Apple Health
  (startDate = midnight, but creationDate = actual log time)
    |
    v
HKObserverQuery fires in NutritionHealthService (debounced 2s)
    |
    v
queryAndGroupMeals() queries all individual samples for today
  1. Queries carbs, fat, protein, fiber samples in parallel
  2. Filters out Trio's own writes (org.nightscout bundle prefix)
  3. Reads each sample's private creationDate via KVC
  4. Sorts all samples by creationDate
  5. Groups samples within 15-minute windows into meals
  6. Publishes [DetectedMeal] via mealsDetected publisher
    |
    v
CronometerMealDetector subscribes, applies isDosed state,
publishes final meal list for the UI
    |
    v
User sees meals in Treatments view, selects one, taps dose
    |
    v
Selected meal carbs populate the carbs field
    |
    v
Standard oref bolus calculator takes over
```

### Why creationDate Instead of startDate?

Cronometer (and some other apps) write all Apple Health entries with **midnight timestamps** (`startDate = 12:00 AM`). A raw HealthKit query using `startDate` would show every meal at midnight.

The private `HKObject.creationDate` property (the "Date Added to Health" field shown in the Apple Health app) reflects **when the data was actually written to HealthKit** — i.e., when the user logged the food. We access this via KVC: `sample.value(forKey: "creationDate") as? Date`.

This is a private API, which is acceptable because Trio is a sideloaded app (not distributed via the App Store).

---

## 2. Data Models

### DetectedMeal

The model for a single detected meal. Used by both the detection system and the UI.

**File:** `Trio/Sources/Models/SmartSenseModels.swift`

```swift
struct DetectedMeal: Identifiable, Codable, Equatable {
    let id: UUID
    let detectedAt: Date       // creationDate from HealthKit (when user logged the food)
    let carbs: Double          // grams
    let fat: Double            // grams
    let protein: Double        // grams
    let fiber: Double          // grams
    let source: String         // e.g. "cronometer"
    var isDosed: Bool          // Whether this meal was already dosed

    var label: String          // "Meal at 6:04 PM" (computed from detectedAt)
    var estimatedCalories: Int // (carbs * 4) + (fat * 9) + (protein * 4)
    var minutesAgo: Double     // minutes since detectedAt
}
```

---

## 3. HealthKit Nutrition Observer

**File:** `Trio/Sources/Services/HealthKit/NutritionHealthService.swift`

### Responsibilities

- Registers `HKObserverQuery` on all four macro types (carbs, fat, protein, fiber)
- Enables background delivery for carbs (immediate frequency)
- On each observer callback (debounced 2s), queries all individual samples for today
- Groups samples by `creationDate` into meals
- Publishes `[DetectedMeal]` via `mealsDetected` publisher

### Observer Setup

```swift
func startObserving() {
    Task {
        await fetchAndPublishMeals()  // initial fetch

        for typeID in nutritionTypes {
            // Register HKObserverQuery for each macro type
            // On callback: scheduleFetch() (debounced)
        }

        // Enable background delivery for carbs
        healthStore.enableBackgroundDelivery(for: carbType, frequency: .immediate)
    }
}
```

### Sample Query

Queries individual `HKQuantitySample` objects for today, filtered to exclude Trio's own writes:

```swift
private func queryExternalSamples(for identifier: HKQuantityTypeIdentifier) async -> [HKQuantitySample] {
    // HKSampleQuery with todayPredicate
    // Filter: !bundleIdentifier.hasPrefix("org.nightscout")
    // Returns raw HKQuantitySample array
}
```

### creationDate Access (Private API)

```swift
let date = (sample.value(forKey: "creationDate") as? Date) ?? sample.endDate
```

Falls back to `endDate` if the private property is unavailable.

---

## 4. Meal Grouping Algorithm

**File:** `Trio/Sources/Services/HealthKit/NutritionHealthService.swift` — `queryAndGroupMeals()`

This is the heart of meal detection. It's simple:

**Step 1 — Query all samples:**
Query carbs, fat, protein, and fiber samples in parallel. Each returns `[HKQuantitySample]`.

**Step 2 — Tag and sort:**
Each sample is tagged with its macro type (`carbs`/`fat`/`protein`/`fiber`), its `creationDate`, and its gram value. All samples are sorted by `creationDate`.

**Step 3 — Group into meals (15-minute window):**
Walk through the sorted samples. If a sample's `creationDate` is within 15 minutes of the current group's start time, add it to the group. Otherwise, start a new group.

```swift
for sample in allSamples {
    if sample.creationDate is within 15 min of current group's start {
        // Add to current group (accumulate grams by macro type)
    } else {
        // Start new group
    }
}
```

**Step 4 — Filter trivial entries:**
Only groups where at least one macro exceeds 1g become `DetectedMeal` objects.

**Result:** A `[DetectedMeal]` array, each with accurate `detectedAt` timestamps from `creationDate` and summed macro values from all samples in the group.

---

## 5. Meal Loading in the State Model

**File:** `Trio/Sources/Modules/Treatments/TreatmentsStateModel.swift`

### State Properties

```swift
var detectedMeals: [DetectedMeal] = []
var selectedMealID: UUID?
```

### Observation Setup

```swift
if settings.readNutritionFromHealth {
    cronometerMealDetector.startObserving()

    cronometerMealDetector.mealsPublisher
        .receive(on: DispatchQueue.main)
        .sink { [weak self] meals in
            self?.detectedMeals = meals
        }
        .store(in: &subscriptions)
}
```

### Meal Selection

```swift
func selectDetectedMeal(_ meal: DetectedMeal) {
    carbs = Decimal(meal.carbs)
    fat = Decimal(meal.fat)
    protein = Decimal(meal.protein)
    date = meal.detectedAt      // Pre-fills time picker with actual meal time
    selectedMealID = meal.id
}
```

---

## 6. UI: Meal Feed & Selection

**File:** `Trio/Sources/Modules/Treatments/View/TreatmentsRootView.swift`

Detected meals from the last 4 hours are shown in the treatments view:

```swift
// Filter to recent meals
state.detectedMeals.filter { $0.detectedAt > Date().addingTimeInterval(-4 * 60 * 60) }
```

Each meal is displayed via `CronometerMealPickerView`. When selected, `selectDetectedMeal()` populates the carbs, fat, protein, and timestamp fields.

---

## 7. UI: Meal Card

Displays a single detected meal with:
- Macro breakdown (carbs/fat/protein with colored badges)
- Time detected (from `detectedAt`)
- Source label
- Dosed indicator

---

## 8. UI: Manual Meal Entry

A form for entering macros manually, separate from the detected meal flow.

---

## 9. Integration Point: Feeding Carbs into oref

When the user selects a detected meal:

1. `selectDetectedMeal()` sets `carbs`, `fat`, `protein`, and `date` on the state
2. The treatment time picker shows the actual meal time (not current time)
3. When the user confirms, `markAsDosed()` is called on the meal
4. Standard oref bolus calculator handles the rest

---

## 10. Settings & Permissions

### Required Setting

```swift
// In TrioSettings:
var readNutritionFromHealth: Bool = false
```

When enabled:
1. Requests HealthKit read permissions for dietary carbs, fat, protein, fiber
2. Starts `HKObserverQuery` observers for all four types
3. Enables background delivery for carbs

### HealthKit Permissions

```swift
static let nutritionReadPermissions: Set<HKObjectType> = [
    HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
    HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!,
    HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
    HKQuantityType.quantityType(forIdentifier: .dietaryFiber)!
]
```

---

## 11. File Inventory

### Active Files

| File | Purpose | Key Classes/Structs |
|------|---------|-------------------|
| `Trio/Sources/Services/HealthKit/NutritionHealthService.swift` | HealthKit observer + sample-based meal grouping | `NutritionHealthService` |
| `Trio/Sources/Services/SmartSense/CronometerMealDetector.swift` | Subscribes to meal updates, manages isDosed state | `CronometerMealDetector`, `BaseCronometerMealDetector` |
| `Trio/Sources/Models/SmartSenseModels.swift` | DetectedMeal model | `DetectedMeal` |
| `Trio/Sources/Modules/Treatments/TreatmentsStateModel.swift` | Wires meals into treatment flow | `selectDetectedMeal()`, `markAsDosed()` |
| `Trio/Sources/Modules/Treatments/View/TreatmentsRootView.swift` | Displays detected meals in UI | Meal picker section |

### Removed / Deprecated

| File | Was | Status |
|------|-----|--------|
| `Trio/Sources/Models/NutritionSnapshot.swift` | Snapshot store, cumulative-delta inference | Gutted — replaced by direct sample grouping |

---

## Summary

The meal detection system:

1. **Observes HealthKit** for nutrition changes via `HKObserverQuery` with background delivery
2. **Queries individual samples** for today's carbs, fat, protein, and fiber
3. **Reads `creationDate`** (private API via KVC) to get the actual time food was logged
4. **Groups samples** within 15-minute windows into meals
5. **Publishes meals** to the UI, where the user can select and dose

No snapshots, no cumulative totals, no deltas. Just read samples, group by time, display.

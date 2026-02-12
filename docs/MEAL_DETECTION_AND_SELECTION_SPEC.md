# Meal Detection & Selection System — Technical Specification

This document describes the meal detection and selection system extracted from the V2 dosing flow. The goal is to enable re-implementation of **only** this subsystem on a clean base Trio codebase, wiring selected meal carbs into the standard oref treatment flow (no V2 curve engine, no split dosing, no outcome learning).

---

## Table of Contents

1. [Overview & Data Flow](#1-overview--data-flow)
2. [Data Models](#2-data-models)
3. [HealthKit Nutrition Observer](#3-healthkit-nutrition-observer)
4. [Snapshot Store & Meal Inference](#4-snapshot-store--meal-inference)
5. [Meal Loading in the State Model](#5-meal-loading-in-the-state-model)
6. [UI: Meal Feed & Selection](#6-ui-meal-feed--selection)
7. [UI: Meal Card](#7-ui-meal-card)
8. [UI: Manual Meal Entry](#8-ui-manual-meal-entry)
9. [Integration Point: Feeding Carbs into V1 oref](#9-integration-point-feeding-carbs-into-v1-oref)
10. [Settings & Permissions](#10-settings--permissions)
11. [File Inventory](#11-file-inventory)

---

## 1. Overview & Data Flow

```
User logs food in Cronometer (or other Apple Health writer)
    |
    v
Cronometer writes nutrition samples to Apple Health
    |
    v
HKObserverQuery fires in NutritionHealthService
    |
    v
recordNutritionSnapshot() queries today's cumulative totals
    |
    v
NutritionSnapshotStore saves snapshot with CURRENT timestamp
    |
    v
User opens Treatments page
    |
    v
loadV2DetectedMeals() called (onAppear + pull-to-refresh)
  1. Triggers a fresh snapshot via fetchLatestMealDelta()
  2. Calls inferredMealEvents(forLastHours: 8) on the snapshot store
  3. Snapshot deltas are computed (consecutive snapshot diffs)
  4. Raw deltas within 15 min of each other are merged into one meal
  5. Each meal becomes a V2DetectedMeal shown in the feed
    |
    v
User selects meals via checkboxes, taps "Continue"
    |
    v
Combined carbs from selected meals populate the carbs field
    |
    v
Standard oref bolus calculator takes over
```

### Why Snapshots Instead of Raw HealthKit Queries?

Cronometer writes all Apple Health entries with **midnight timestamps** (cumulative daily totals). A raw HealthKit query would show every meal at 12:00 AM. The snapshot system captures the **actual time the observer fired** — i.e., when the user logged the food — preserving correct meal timestamps.

---

## 2. Data Models

### V2DetectedMeal

The UI-facing model for a single detected meal. Displayed in the meal feed.

**File:** `Trio/Sources/Models/V2DetectedMeal.swift`

```swift
struct V2DetectedMeal: Identifiable {
    let id = UUID()
    let date: Date          // When the meal was detected (observer fire time)
    let label: String       // "Breakfast", "Lunch", "Dinner", "Snack", "Manual Entry"
    let carbs: Double       // grams
    let fat: Double         // grams
    let protein: Double     // grams
    let fiber: Double       // grams
    let source: String      // "Cronometer", "Apple Health", "Manual"
    let isDosed: Bool       // Whether this meal was already dosed today
    let healthKitID: String? // HealthKit sample ID (for deduplication, currently nil)

    var estimatedCalories: Int {
        Int(carbs * 4 + fat * 9 + protein * 4)
    }

    var minutesAgo: Double {
        Date().timeIntervalSince(date) / 60
    }

    var isLate: Bool {
        minutesAgo > 60
    }
}
```

### NutritionSnapshot

A point-in-time capture of today's cumulative nutrition totals from Apple Health.

**File:** `Trio/Sources/Models/NutritionSnapshot.swift`

```swift
struct NutritionSnapshot: JSON, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date              // When the observer fired (= approximate meal time)
    let cumulativeCarbs: Double
    let cumulativeFat: Double
    let cumulativeProtein: Double
    let cumulativeFiber: Double
    let forDate: Date                // The calendar day these totals apply to
}
```

### InferredMealEvent

A meal derived from the delta between two consecutive snapshots.

**File:** `Trio/Sources/Models/NutritionSnapshot.swift`

```swift
struct InferredMealEvent: Identifiable, Equatable {
    let id: UUID
    let detectedAt: Date       // When we noticed the change (approximate meal time)
    let carbsDelta: Double
    let fatDelta: Double
    let proteinDelta: Double
    let fiberDelta: Double

    var totalCalories: Double {
        (carbsDelta * 4) + (fatDelta * 9) + (proteinDelta * 4)
    }

    var minutesAgo: Double {
        Date().timeIntervalSince(detectedAt) / 60
    }

    var timeAgoString: String {
        let mins = Int(minutesAgo)
        if mins < 60 {
            return "\(mins) min ago"
        } else {
            let hours = mins / 60
            let remainingMins = mins % 60
            if remainingMins == 0 {
                return "\(hours)h ago"
            }
            return "\(hours)h \(remainingMins)m ago"
        }
    }
}
```

### HealthNutritionEntry

A unified nutrition entry merged from individual HealthKit samples.

**File:** `Trio/Sources/Models/HealthNutrition.swift`

```swift
struct HealthNutritionEntry: JSON, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let carbs: Double
    let fat: Double
    let protein: Double
    let fiber: Double
    let source: String
}
```

---

## 3. HealthKit Nutrition Observer

**File:** `Trio/Sources/Services/HealthKit/NutritionHealthService.swift`

### Protocol

```swift
protocol NutritionHealthService {
    var isAvailable: Bool { get }
    func requestPermissions() async -> Bool
    func fetchNutritionEntries(from startDate: Date, to endDate: Date) async throws -> [HealthNutritionEntry]
    func startObservingNutritionChanges()
    func stopObservingNutritionChanges()
    func fetchLatestMealDelta() async -> InferredMealEvent?
}
```

### Auto-Start on Launch

The observer starts automatically at app launch if `readNutritionFromHealth` is enabled in settings:

```swift
init(resolver: Resolver) {
    injectServices(resolver)
    if settingsManager.settings.readNutritionFromHealth {
        startObservingNutritionChanges()
    }
}
```

### Observer Query Setup

Registers an `HKObserverQuery` on `.dietaryCarbohydrates`. When HealthKit detects new carb samples (from any external app), the handler fires and records a snapshot:

```swift
func startObservingNutritionChanges() {
    guard isAvailable else { return }
    guard observerQuery == nil else { return }

    guard let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) else { return }

    let query = HKObserverQuery(sampleType: carbType, predicate: nil) { [weak self] _, completionHandler, error in
        guard let self = self else { completionHandler(); return }
        if let error = error { completionHandler(); return }

        Task {
            await self.recordNutritionSnapshot()
            completionHandler()
        }
    }

    healthKitStore.execute(query)
    observerQuery = query

    // Background delivery so we get notified even when app is backgrounded
    healthKitStore.enableBackgroundDelivery(for: carbType, frequency: .immediate) { _, _ in }

    // Record an initial snapshot
    Task { await recordNutritionSnapshot() }
}
```

### Recording a Snapshot

Queries today's cumulative totals across all four macros, saves to the snapshot store:

```swift
private func recordNutritionSnapshot() async {
    let today = calendar.startOfDay(for: Date())
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

    do {
        let entries = try await fetchNutritionEntries(from: today, to: tomorrow)
        let totalCarbs = entries.reduce(0) { $0 + $1.carbs }
        let totalFat = entries.reduce(0) { $0 + $1.fat }
        let totalProtein = entries.reduce(0) { $0 + $1.protein }
        let totalFiber = entries.reduce(0) { $0 + $1.fiber }

        let snapshot = NutritionSnapshot(
            cumulativeCarbs: totalCarbs,
            cumulativeFat: totalFat,
            cumulativeProtein: totalProtein,
            cumulativeFiber: totalFiber,
            forDate: today
        )
        snapshotStore.saveSnapshot(snapshot)
    } catch { }
}
```

### Fetching HealthKit Samples (Filtering Trio's Own Entries)

Queries each macro type separately, filters out entries written by Trio itself (bundle prefix `org.nightscout`), then merges samples from the same source within 2 seconds of each other into unified `HealthNutritionEntry` objects:

```swift
private func fetchSamples(
    type identifier: HKQuantityTypeIdentifier,
    from startDate: Date,
    to endDate: Date
) async throws -> [HKQuantitySample] {
    // ... standard HKSampleQuery ...

    // Filter out Trio-originated entries
    let externalSamples = quantitySamples.filter { sample in
        let bundleId = sample.sourceRevision.source.bundleIdentifier
        return !bundleId.hasPrefix("org.nightscout")
    }
    return externalSamples
}
```

### Sample Merging

Samples from the same source with timestamps within 2 seconds are considered the same food item:

```swift
private func mergeNutritionSamples(
    carbs: [HKQuantitySample],
    fats: [HKQuantitySample],
    proteins: [HKQuantitySample],
    fibers: [HKQuantitySample]
) -> [HealthNutritionEntry] {
    struct SampleKey: Hashable {
        let timestamp: Int  // seconds since ref date, rounded to nearest 2s
        let source: String
    }

    // Key function: round timestamp to nearest 2 seconds, group by source
    func key(for sample: HKQuantitySample) -> SampleKey {
        let ts = Int(sample.startDate.timeIntervalSinceReferenceDate / 2) * 2
        return SampleKey(timestamp: ts, source: sample.sourceRevision.source.name)
    }

    // Iterate all four macro sample arrays, accumulate into dictionary by key
    // Then map dictionary values to [HealthNutritionEntry], sorted by date
}
```

### fetchLatestMealDelta()

Called when user opens the meal feed or taps "Log in Cronometer" button. Queries current HealthKit totals, saves a fresh snapshot, and returns the delta since the previous snapshot:

```swift
func fetchLatestMealDelta() async -> InferredMealEvent? {
    let today = calendar.startOfDay(for: Date())
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

    let entries = try await fetchNutritionEntries(from: today, to: tomorrow)
    let totalCarbs = entries.reduce(0) { $0 + $1.carbs }
    let totalFat = entries.reduce(0) { $0 + $1.fat }
    let totalProtein = entries.reduce(0) { $0 + $1.protein }
    let totalFiber = entries.reduce(0) { $0 + $1.fiber }

    return snapshotStore.recordAndComputeLatestMeal(
        currentCarbs: totalCarbs,
        currentFat: totalFat,
        currentProtein: totalProtein,
        currentFiber: totalFiber
    )
}
```

---

## 4. Snapshot Store & Meal Inference

**File:** `Trio/Sources/Models/NutritionSnapshot.swift` (class `NutritionSnapshotStore`)

### Storage

- Singleton: `NutritionSnapshotStore.shared`
- Snapshots persisted to `~/Documents/nutrition_snapshots.json`
- Dose timestamps persisted to `~/Documents/v2_dose_timestamps.json`
- 14-day retention with automatic pruning

### Core Algorithm: `inferredMealEvents(for date: Date)`

This is the heart of meal detection. It converts raw nutrition snapshots into discrete meal events.

**Step 1 — Load & sort snapshots for the given day:**
```swift
let snapshots = snapshotsForDate(date).sorted { $0.timestamp < $1.timestamp }
```

**Step 2 — Bootstrap case (single snapshot):**
If only one snapshot exists, the entire day's cumulative intake is treated as one meal:
```swift
if snapshots.count == 1 {
    let snap = snapshots[0]
    guard snap.cumulativeCarbs > 1 || snap.cumulativeFat > 1 || snap.cumulativeProtein > 1 else { return [] }
    return [InferredMealEvent(detectedAt: snap.timestamp, carbsDelta: snap.cumulativeCarbs, ...)]
}
```

**Step 3 — First pass: compute raw deltas between consecutive snapshots:**

The first snapshot is compared against a midnight baseline of zeros. Each subsequent snapshot is compared to its predecessor. Only deltas where at least one macro exceeds 1g are kept:

```swift
// First snapshot vs midnight baseline
if first.cumulativeCarbs > 1 || first.cumulativeFat > 1 || first.cumulativeProtein > 1 {
    rawEvents.append((detectedAt: first.timestamp, carbsDelta: first.cumulativeCarbs, ...))
}

// Subsequent snapshots vs previous
for i in 1 ..< snapshots.count {
    let carbDelta = curr.cumulativeCarbs - prev.cumulativeCarbs
    // ... same for fat, protein, fiber
    if carbDelta > 1 || fatDelta > 1 || proteinDelta > 1 {
        rawEvents.append(...)
    }
}
```

**Step 4 — Load dose timestamps (meal group boundaries):**

When a dose is applied, a timestamp is recorded. This "closes" the current meal group. Any new deltas after the dose — even within 15 minutes — become a separate meal. Example: dinner dosed, then dessert logged 13 min later = two meals.

```swift
let doseTimestamps = loadDoseTimestamps().sorted()
```

**Step 5 — Second pass: merge raw deltas within 15 minutes into single meals:**

```swift
let mealGroupingWindow: TimeInterval = 15 * 60  // 15 minutes

for i in 1 ..< rawEvents.count {
    let gap = thisTime.timeIntervalSince(prevTime)
    let doseBetween = doseTimestamps.contains { $0 > prevTime && $0 <= thisTime }

    if gap <= mealGroupingWindow, !doseBetween {
        // Same meal — accumulate macros
        currentCarbs += rawEvents[i].carbsDelta
        // ...
    } else {
        // New meal — finalize current, start new
        meals.append(InferredMealEvent(detectedAt: currentTime, carbsDelta: currentCarbs, ...))
        currentCarbs = rawEvents[i].carbsDelta
        // ...
    }
}
// Don't forget the last meal
meals.append(...)
```

### `recordAndComputeLatestMeal()`

Used for the real-time "Cronometer button" flow. Saves a fresh snapshot, then walks backwards from the end grouping snapshots within the 15-minute window. The baseline is the snapshot just before this cluster:

```swift
func recordAndComputeLatestMeal(
    currentCarbs: Double, currentFat: Double,
    currentProtein: Double, currentFiber: Double
) -> InferredMealEvent? {
    // Save fresh snapshot
    // Walk backwards grouping by 15-min window
    // Baseline = snapshot before cluster (or midnight zeros)
    // Return delta between baseline and current totals
}
```

### `inferredMealEvents(forLastHours hours: Int)`

Convenience method that covers today + yesterday (if the window crosses midnight):

```swift
func inferredMealEvents(forLastHours hours: Int) -> [InferredMealEvent] {
    let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
    var allEvents = inferredMealEvents(for: today)
    if cutoff < today {
        allEvents += inferredMealEvents(for: yesterday)
    }
    return allEvents.filter { $0.detectedAt >= cutoff }.sorted { $0.detectedAt < $1.detectedAt }
}
```

### Dose Timestamp Recording

```swift
func recordDoseTimestamp() {
    var timestamps = loadDoseTimestamps()
    timestamps.append(Date())
    // Prune old, save to v2_dose_timestamps.json
}
```

---

## 5. Meal Loading in the State Model

**File:** `Trio/Sources/Modules/Treatments/TreatmentsStateModel.swift`

### State Properties Needed

```swift
// In the treatments state model:
var v2DetectedMeals: [V2DetectedMeal] = []    // Meals shown in the feed
```

### `loadV2DetectedMeals()`

Called on view appear and pull-to-refresh. The complete flow:

```swift
@MainActor
func loadV2DetectedMeals() async {
    // 1. Trigger a fresh snapshot (catches entries since last observer fire)
    _ = await nutritionHealthService.fetchLatestMealDelta()

    // 2. Get inferred meals from last 8 hours of snapshots
    let inferredMeals = NutritionSnapshotStore.shared.inferredMealEvents(forLastHours: 8)

    // 3. Check which meals were already dosed today
    //    (In the simplified version, this could check against today's carb entries
    //    in Core Data instead of V2 outcomes. Or just skip isDosed entirely.)
    //
    //    Original V2 used macro fingerprinting against V2OutcomeLearningStore:
    //    let isDosed = todayOutcomes.contains(where: {
    //        abs($0.carbs - event.carbsDelta) < 2.0 &&
    //        abs($0.fat - event.fatDelta) < 2.0 &&
    //        abs($0.protein - event.proteinDelta) < 2.0
    //    })

    // 4. Build V2DetectedMeal array
    var meals: [V2DetectedMeal] = []
    for event in inferredMeals {
        guard event.carbsDelta > 1 || event.fatDelta > 1 || event.proteinDelta > 1 else { continue }

        meals.append(V2DetectedMeal(
            date: event.detectedAt,
            label: inferMealLabel(for: event.detectedAt),
            carbs: event.carbsDelta,
            fat: event.fatDelta,
            protein: event.proteinDelta,
            fiber: event.fiberDelta,
            source: "Cronometer",
            isDosed: false,  // simplified: implement your own check or remove
            healthKitID: nil
        ))
    }

    v2DetectedMeals = meals.sorted { $0.date > $1.date }  // Most recent first
}
```

### `addManualV2Meal()`

Adds a manually entered meal to the top of the feed:

```swift
@MainActor
func addManualV2Meal(carbs: Decimal, fat: Decimal, protein: Decimal, fiber: Decimal) {
    let meal = V2DetectedMeal(
        date: Date(),
        label: "Manual Entry",
        carbs: Double(truncating: carbs as NSDecimalNumber),
        fat: Double(truncating: fat as NSDecimalNumber),
        protein: Double(truncating: protein as NSDecimalNumber),
        fiber: Double(truncating: fiber as NSDecimalNumber),
        source: "Manual",
        isDosed: false,
        healthKitID: nil
    )
    v2DetectedMeals.insert(meal, at: 0)
}
```

### `recordCronometerBaseline()`

Called before opening the Cronometer app, so we can detect what the user logs:

```swift
@MainActor
func recordCronometerBaseline() async {
    _ = await nutritionHealthService.fetchLatestMealDelta()
}
```

### `inferMealLabel(for:)`

Auto-labels meals based on time of day:

```swift
private func inferMealLabel(for date: Date) -> String {
    let hour = Calendar.current.component(.hour, from: date)
    switch hour {
    case 5 ..< 10:  return "Breakfast"
    case 10 ..< 12: return "Morning Snack"
    case 12 ..< 14: return "Lunch"
    case 14 ..< 17: return "Afternoon Snack"
    case 17 ..< 21: return "Dinner"
    default:         return "Snack"
    }
}
```

---

## 6. UI: Meal Feed & Selection

**File:** `Trio/Sources/Modules/Treatments/View/V2TreatmentView.swift`

This is the meal feed view. In the simplified version, it would be a step before the existing V1 treatments form (or an embedded section within it).

### State

```swift
@State private var selectedMealIndices: Set<Int> = []
@State private var manualEntryCarbs: Decimal = 0
@State private var manualEntryFat: Decimal = 0
@State private var manualEntryProtein: Decimal = 0
@State private var manualEntryFiber: Decimal = 0
@State private var showManualEntry = false
```

### Computed Properties

```swift
private var combinedCarbs: Double {
    var total = 0.0
    for index in selectedMealIndices {
        guard index < state.v2DetectedMeals.count else { continue }
        total += state.v2DetectedMeals[index].carbs
    }
    return total
}

// Same pattern for combinedFat, combinedProtein, combinedFiber

private var hasSelection: Bool {
    !selectedMealIndices.isEmpty
}

private var selectedMealsList: [V2DetectedMeal] {
    selectedMealIndices.compactMap { idx in
        idx < state.v2DetectedMeals.count ? state.v2DetectedMeals[idx] : nil
    }
}
```

### View Structure

```swift
List {
    // 1. Selected meals summary bar (only shown when meals are selected)
    if hasSelection {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedMealIndices.count) item(s) selected")
                    HStack(spacing: 12) {
                        macroLabel("C", value: combinedCarbs, color: .orange)
                        macroLabel("F", value: combinedFat, color: .yellow)
                        macroLabel("P", value: combinedProtein, color: .red)
                        if combinedFiber > 0 {
                            macroLabel("Fiber", value: combinedFiber, color: .green)
                        }
                    }
                }
                Spacer()
            }
        }
        .listRowBackground(Color.blue.opacity(0.1))
    }

    // 2. Meal list
    Section(header: Text("Recent Meals & Nutrition")) {
        if state.v2DetectedMeals.isEmpty {
            // Empty state: fork.knife.circle icon + "No recent meals detected"
        } else {
            ForEach(Array(state.v2DetectedMeals.enumerated()), id: \.offset) { index, meal in
                V2MealCardView(
                    meal: meal,
                    isSelected: selectedMealIndices.contains(index),
                    isDosed: meal.isDosed,
                    onToggle: {
                        if selectedMealIndices.contains(index) {
                            selectedMealIndices.remove(index)
                        } else {
                            selectedMealIndices.insert(index)
                        }
                    }
                )
            }
        }
    }

    // 3. Action buttons
    Section {
        // "Enter meal manually" -> showManualEntry = true
        // "Log in Cronometer" -> recordCronometerBaseline() then openURL("cronometer://")
        // "Correction bolus only" -> clear selection, go to treatment form with 0 carbs
    }

    // 4. Continue button
    Section {
        Button("Continue") {
            // Set state.carbs = Decimal(combinedCarbs)
            // Navigate to the standard treatment form
        }
        .disabled(!hasSelection)
    }
}
.refreshable { await state.loadV2DetectedMeals() }
.onAppear { Task { await state.loadV2DetectedMeals() } }
.sheet(isPresented: $showManualEntry) {
    V2ManualMealEntryView(...)
}
```

### Helper

```swift
private func macroLabel(_ label: String, value: Double, color: Color) -> some View {
    HStack(spacing: 2) {
        Text(label).font(.caption2).foregroundStyle(color)
        Text("\(Int(value))g").font(.caption.weight(.medium))
    }
}
```

---

## 7. UI: Meal Card

**File:** `Trio/Sources/Modules/Treatments/View/V2MealCardView.swift`

Complete, self-contained view (96 lines). No dependencies on V2 engine.

```swift
struct V2MealCardView: View {
    let meal: V2DetectedMeal
    let isSelected: Bool
    let isDosed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                // Checkbox: checkmark.circle.fill (blue) or circle (secondary)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    // Row 1: Meal label + time
                    HStack {
                        Text(meal.label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(meal.date, style: .time).font(.caption).foregroundStyle(.secondary)
                    }

                    // Row 2: Macro chips (C/F/P with colored badges)
                    HStack(spacing: 10) {
                        macroChip("C", value: meal.carbs, color: .orange)
                        macroChip("F", value: meal.fat, color: .yellow)
                        macroChip("P", value: meal.protein, color: .red)
                    }

                    // Row 3: Source + time ago + dosed badge
                    HStack(spacing: 6) {
                        if isDosed {
                            // Green checkmark + "Dosed" text
                        }
                        Text("via \(meal.source)").font(.caption2).foregroundStyle(.secondary)
                        Text(timeAgoText).font(.caption2).foregroundStyle(.secondary)
                    }

                    // Row 4: Warning if re-dosing
                    if isDosed && isSelected {
                        Text("This meal was already dosed. Selecting it will add additional insulin coverage.")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
            .opacity(isDosed && !isSelected ? 0.5 : 1.0)  // Dim already-dosed meals
        }
        .buttonStyle(.plain)
    }

    private var timeAgoText: String {
        let minutes = Date().timeIntervalSince(meal.date) / 60
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(Int(minutes)) min ago" }
        let hours = minutes / 60
        if hours < 1.5 { return "1 hour ago" }
        return String(format: "%.1fh ago", hours)
    }

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
            Text("\(Int(value))g").font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }
}
```

---

## 8. UI: Manual Meal Entry

**File:** `Trio/Sources/Modules/Treatments/View/V2ManualMealEntryView.swift`

A simple form sheet for entering macros manually. Complete and self-contained (83 lines).

```swift
struct V2ManualMealEntryView: View {
    @Binding var carbs: Decimal
    @Binding var fat: Decimal
    @Binding var protein: Decimal
    @Binding var fiber: Decimal

    let onAdd: (Decimal, Decimal, Decimal, Decimal) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Meal Macros")) {
                    // Four rows: Carbs (g), Fat (g), Protein (g), Fiber (g)
                    // Each: HStack { Text("Label") Spacer() TextField("0", ...) }
                    // TextField: .keyboardType(.numberPad), .frame(width: 80)
                    // NumberFormatter: .decimal, maxIntegerDigits=3, maxFractionDigits=0
                }

                Section {
                    Button("Add Meal") { onAdd(carbs, fat, protein, fiber) }
                        .disabled(carbs <= 0 && fat <= 0 && protein <= 0)
                }
            }
            .navigationTitle("Manual Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }
}
```

The parent calls `state.addManualV2Meal(carbs:fat:protein:fiber:)` in the `onAdd` closure, which inserts the meal at position 0 of the feed.

---

## 9. Integration Point: Feeding Carbs into V1 oref

This is where the V2 dosing engine was invoked. **For the simplified version, replace this with a simple carb summation.**

### What V2 Did (to be removed)

```swift
// OLD: V2 ran MacroAbsorptionEngine to compute split dosing
state.computeV2CurveParamsForSelectedMeals(meals)  // DELETE
```

### What the Simplified Version Should Do

When the user taps "Continue" after selecting meals:

```swift
private func applySelectionToState() {
    // Sum carbs from all selected meals
    state.carbs = Decimal(combinedCarbs)

    // Optionally set the meal date to the earliest selected meal's timestamp
    if let earliest = selectedMealsList.min(by: { $0.date < $1.date }) {
        state.date = earliest.date
    }

    // Update forecasts and calculate insulin via standard oref
    Task {
        await state.updateForecasts()
        state.insulinCalculated = await state.calculateInsulin()
    }
}
```

Then navigate to the standard V1 treatment form, which already has:
- Forecast chart
- Bolus recommendation
- Fatty meal / Super bolus toggles
- Meal presets
- External insulin toggle
- Confirm button

The carbs field will be pre-populated from the selected meals. User can adjust if needed. Standard oref handles everything from there.

### Recording Dose Timestamp

After the meal is saved (in `invokeTreatmentsTask()`), record a dose timestamp so subsequent Cronometer entries become a separate meal:

```swift
NutritionSnapshotStore.shared.recordDoseTimestamp()
```

---

## 10. Settings & Permissions

### Required Setting

```swift
// In TrioSettings:
var readNutritionFromHealth: Bool = false
```

This setting is already exposed in the Apple Health settings view (`AppleHealthKitRootView`). When enabled, it:
1. Requests HealthKit read permissions for dietary carbs, fat, protein, fiber
2. Starts the `HKObserverQuery` for background nutrition monitoring
3. Enables background delivery for immediate notifications

### HealthKit Permissions

```swift
// In AppleHealthConfig:
static let nutritionReadPermissions: Set<HKObjectType> = [
    HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
    HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!,
    HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
    HKQuantityType.quantityType(forIdentifier: .dietaryFiber)!
]
```

### Dependency Injection

The `NutritionHealthService` is registered via Swinject and injected into the treatments state model:

```swift
@Injected() var nutritionHealthService: NutritionHealthService!
```

---

## 11. File Inventory

### Files to Keep / Re-implement

| File | Purpose | Lines |
|------|---------|-------|
| `Trio/Sources/Models/V2DetectedMeal.swift` | Detected meal model | 31 |
| `Trio/Sources/Models/NutritionSnapshot.swift` | Snapshot, InferredMealEvent, NutritionSnapshotStore | ~753 (also contains CarbDecayModel, LowEpisode — only snapshot/meal parts needed) |
| `Trio/Sources/Models/HealthNutrition.swift` | HealthNutritionEntry model | ~20 |
| `Trio/Sources/Services/HealthKit/NutritionHealthService.swift` | HealthKit observer + snapshot recording | 366 |
| `Trio/Sources/Modules/Treatments/View/V2MealCardView.swift` | Meal card UI | 96 |
| `Trio/Sources/Modules/Treatments/View/V2ManualMealEntryView.swift` | Manual entry form | 83 |
| `Trio/Sources/Modules/Treatments/View/V2TreatmentView.swift` | Meal feed container (simplify: remove dosePreview step) | 281 |

### State Model Methods to Keep

From `TreatmentsStateModel.swift`:
- `loadV2DetectedMeals()` — load meals from snapshot store
- `addManualV2Meal(carbs:fat:protein:fiber:)` — add manual meal to feed
- `recordCronometerBaseline()` — capture baseline before opening Cronometer
- `inferMealLabel(for:)` — time-based meal naming

### State Model Properties to Keep

```swift
var v2DetectedMeals: [V2DetectedMeal] = []
```

### Files to NOT Carry Over (V2 Dosing Engine)

- `MacroAbsorptionEngine.swift` — three-curve engine
- `MacroOnBoardCalculator.swift` — macro absorption tracking
- `MacrosOnBoardTracker.swift` — macro on-board tracking
- `V2CurveOutcomeLearning.swift` — outcome learning service
- `V2MealOutcomeStored+CoreData*.swift` — outcome Core Data entity
- `V2DosePreviewView.swift` — dose preview step
- `V2ForecastChart.swift` — two-line forecast chart
- `V2MacroDosingSettingsView.swift` — V2 settings
- `V2MacroHubView.swift` — macro hub
- `V2OutcomeAnalysisView.swift` — outcome analysis
- `V2NutritionSettingsView.swift` — nutrition settings (keep `readNutritionFromHealth` toggle in existing HealthKit settings)
- `V2GarminSettingsView.swift` — Garmin integration
- `V2MacroEngineTests.swift` — V2 engine tests
- All V2 state properties in TreatmentsStateModel (upfront%, curve params, demand factor, pending outcome, etc.)

---

## Summary

The meal detection system is cleanly separable from the V2 dosing engine. It consists of:

1. **A HealthKit observer** that records cumulative nutrition snapshots when external apps write data
2. **A snapshot delta algorithm** that infers discrete meals from consecutive snapshot differences, with 15-minute grouping and dose-aware boundaries
3. **A simple UI** (meal feed + meal cards + manual entry) for browsing and selecting detected meals
4. **A single output**: the total carbs from selected meals, which feeds directly into the standard oref treatment flow

No curve engine, no split dosing, no outcome learning. Just detect meals, let the user pick, and pass carbs to oref.

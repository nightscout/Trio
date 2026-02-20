# Garmin Watch Stale Data: Troubleshooting Log

Chronological record of diagnosing and fixing a 30-50 minute data delay on the Garmin watch face. The watch displayed stale glucose readings while the iOS app and Live Activity showed correct, real-time values.

---

## Symptom

The Garmin watch face consistently showed glucose readings 30-50 minutes behind the Trio iOS app. For example, the app displayed 118 mg/dL while the watch still showed 71 mg/dL from ~30 minutes prior. IOB was also stale. The iOS Lock Screen Live Activity always showed the correct value.

---

## Attempt 1: NSBatchInsertRequest mergeChanges (Failed)

### Hypothesis

`GlucoseStorage.storeGlucoseBatch()` uses `NSBatchInsertRequest` to write glucose readings directly to SQLite. Batch inserts bypass CoreData's persistent store coordinator (PSC) row cache and do not generate `NSManagedObjectContextDidSave` notifications. The `backgroundContext` used by GarminManager to fetch glucose was reading from the stale PSC row cache, never seeing the new rows.

### Fix Applied

Captured the batch insert result, set `resultType = .objectIDs`, and called `NSManagedObjectContext.mergeChanges(fromRemoteContextSave:into:)` with the inserted object IDs, targeting the `viewContext`:

```swift
// GlucoseStorage.swift — storeGlucoseBatch()
batchInsert.resultType = .objectIDs
let result = try context.execute(batchInsert) as? NSBatchInsertResult
if let objectIDs = result?.result as? [NSManagedObjectID] {
    let changes: [AnyHashable: Any] = [NSInsertedObjectsKey: objectIDs]
    NSManagedObjectContext.mergeChanges(
        fromRemoteContextSave: changes,
        into: [CoreDataStack.shared.persistentContainer.viewContext]
    )
}
```

The same pattern was also added to `CarbsStorage` for FPU batch inserts (for consistency).

### Result

**Did not fix the stale data.** Watch still showed glucose 30-50 minutes behind. The `mergeChanges` call successfully invalidated the viewContext cache, but GarminManager was fetching on a separate `backgroundContext` that wasn't in the merge target list.

### Files Modified
- `GlucoseStorage.swift` — added mergeChanges after batch insert
- `CarbsStorage.swift` — added mergeChanges after FPU batch insert

---

## Attempt 2: Fresh CoreData Context Per Fetch (Failed)

### Hypothesis

The reused `backgroundContext` property on GarminManager accumulated a stale PSC row cache over time. Creating a fresh `NSManagedObjectContext` for each fetch would bypass any cached state.

### Fix Applied

- Removed the long-lived `backgroundContext` property from GarminManager
- Parameterized `fetchGlucose()` to accept (and create) a fresh context each call
- Added `glucoseDate` diagnostic field to `GarminWatchState` to show the timestamp of the glucose reading being sent

### Result

**Did not fix the stale data.** Even brand-new contexts returned 30-50 minute old data. This ruled out the PSC row cache theory — the data simply wasn't in CoreData yet when GarminManager fetched.

### Key Insight

The problem wasn't caching at all. CoreData itself was behind. The timing mismatch was:
1. CGM reading arrives
2. GarminManager's Combine triggers fire (glucoseStorage.updatePublisher)
3. GarminManager fetches CoreData — but `storeGlucoseInCoreData` hasn't finished writing yet
4. The fetch returns the previous reading

### Files Modified
- `GarminManager.swift` — fresh context per fetch
- `GarminWatchState.swift` — added `glucoseDate` diagnostic field

---

## Attempt 3: Diagnostic Fields (Partial Success)

### Purpose

Added diagnostic fields to understand the data flow timing:
- `glucoseDate` — timestamp (HH:mm:ss) of the glucose reading in the payload
- `sentAt` — timestamp (HH:mm:ss) when the phone built the payload

### Problem Encountered

`glucoseDate` was not appearing on the watch. Root cause: the field was gated behind `if let glucoseTimestamp = latestGlucose.date` and when date was nil, the field stayed nil. Fixed by adding a `"no-date"` fallback string.

`sentAt` was also not appearing. Hardcoded to `"HELLO"` to test the encoding pipeline, but the user pivoted to a new approach before rebuilding.

### Files Modified
- `GarminWatchState.swift` — added `glucoseDate`, `sentAt` fields
- `GarminManager.swift` — populated diagnostic fields

---

## Attempt 4: Wire Garmin to LiveActivity Data Source (Architectural Fix)

### Hypothesis

The Live Activity (iOS Lock Screen widget) always shows correct, real-time glucose. It uses a long-lived `newTaskContext()` with `automaticallyMergesChangesFromParent = true`, which receives save notifications from other contexts and auto-merges new data. Instead of GarminManager doing its own CoreData fetches (racing against writes), it should consume the same data the Live Activity uses.

### Investigation

Traced the Live Activity data path:

1. `LiveActivityManager` has a `LiveActivityData` object that fetches glucose and determination from CoreData using a long-lived background context
2. That context is created via `CoreDataStack.shared.newTaskContext()`, which sets `automaticallyMergesChangesFromParent = true`
3. When `storeGlucoseInCoreData` does a regular `context.save()` (for single readings), it generates `NSManagedObjectContextDidSave` which auto-merges into the Live Activity's context
4. For batch inserts (count > 1), the `mergeChanges` call we added in Attempt 1 also propagates
5. `pushCurrentContent()` is called when data changes, builds the Live Activity content, and pushes it

### Key Discovery: storeGlucoseInCoreData Branching

```
storeGlucoseInCoreData(glucose):
    if count > 1 → NSBatchInsertRequest (fast, no save notification)
    if count == 1 → regular context.save() (generates save notification)
```

The Live Activity's long-lived context with `automaticallyMergesChangesFromParent = true` catches the regular save notifications. The batch insert path needed the explicit `mergeChanges` call (Attempt 1) to propagate.

### Fix Applied: Major Architecture Change

1. Added `LiveActivitySnapshot` struct to `LiveActivityManager.swift`:
   ```swift
   struct LiveActivitySnapshot {
       let glucose: GlucoseData
       let previousGlucose: GlucoseData?
       let determination: DeterminationData?
       let iob: Decimal?
   }
   ```

2. Added `snapshotPublisher` (PassthroughSubject) to `LiveActivityManager`

3. In `pushCurrentContent()`, publish a snapshot with the current data

4. Rewrote `GarminManager` to:
   - Remove all CoreData fetch code (`fetchGlucose()`, `setupGarminWatchState()`, `backgroundContext`, etc.)
   - Subscribe to `liveActivityManager.snapshotPublisher`
   - Build watch state synchronously from the snapshot via `buildWatchState(from:)`
   - Cache `lastWatchStateData` for poll responses and periodic resends

5. Added `eventualBG` and `insulinSensitivity` fields to `DeterminationData` and the fetch query in `DataManager.swift`

### Result

Build succeeded but **data still not reaching the watch**. Two additional bugs discovered (see Attempt 5).

### Files Modified
- `LiveActivityManager.swift` — added LiveActivitySnapshot, snapshotPublisher, publish in pushCurrentContent
- `GarminManager.swift` — complete rewrite to consume snapshots
- `DeterminationData.swift` — added eventualBG, insulinSensitivity
- `DataManager.swift` — added fields to propertiesToFetch

---

## Attempt 4a: CarbsStorage Revert (Fix for Meals Disappearing)

### Problem

After the changes, all past meals disappeared from the History view. The only meal-related change was the `mergeChanges` addition to `CarbsStorage.swift` (from Attempt 1, "for consistency").

### Fix

Reverted `CarbsStorage.swift` to its original code — removed `resultType = .objectIDs` and the `mergeChanges` call from the FPU batch insert. The FPU batch insert in CarbsStorage doesn't need change propagation because no other context reads FPU data in real time.

### Root Cause (Suspected)

The mergeChanges call with `NSInsertedObjectsKey` may have caused the viewContext to re-fault or invalidate related meal objects, or the resultType change altered the batch insert behavior in a way that corrupted the FPU entries.

### Files Modified
- `CarbsStorage.swift` — reverted to original batch insert code

---

## Attempt 5: Singleton Registration + Snapshot Before Guard (Critical Fix)

### Problem 1: Snapshot gated behind determination guard

In `pushCurrentContent()`, the `snapshotPublisher.send()` was placed AFTER `guard let determination = data.determination`. If determination hadn't loaded yet (e.g., first CGM cycle after launch), the snapshot was never published and Garmin got nothing.

### Fix 1

Moved `snapshotPublisher.send()` before the determination guard. Garmin can display glucose without COB/ISF, so it shouldn't be blocked on determination availability:

```swift
// Publish snapshot BEFORE determination guard
snapshotPublisher.send(LiveActivitySnapshot(
    glucose: bg, previousGlucose: prevGlucose,
    determination: data.determination,  // may be nil
    iob: data.iob
))

guard let determination = data.determination else { return }
// ... Live Activity push continues ...
```

### Problem 2: LiveActivityManager not a singleton (CRITICAL)

`LiveActivityManager` was registered in Swinject's `ServiceAssembly.swift` with the default `.graph` scope. This means every `@Injected() var liveActivityManager: LiveActivityManager` creates a **new instance**. GarminManager got its own private LiveActivityManager whose `snapshotPublisher` was never published to — the real LiveActivityManager (the one receiving data and publishing snapshots) was a completely different object.

### Fix 2

Added `.inObjectScope(.container)` to the LiveActivityManager registration:

```swift
container.register(LiveActivityManager.self) { r in
    LiveActivityManager(resolver: r)
}.inObjectScope(.container)
```

This ensures all consumers resolve the same singleton instance, so GarminManager subscribes to the same publisher that `pushCurrentContent()` publishes to.

### Files Modified
- `LiveActivityManager.swift` — moved snapshot publish before determination guard
- `ServiceAssembly.swift` — added .inObjectScope(.container) for singleton

---

## Attempt 6: ConnectIQ Message Throttle (Queue Overflow Fix)

### Problem

After a clean restart (killed Trio, killed Garmin Connect Mobile, restarted phone), messages were still arriving 30+ minutes late on the watch. The proactive push pipeline used a 10-second Combine `.throttle()`, producing ~6 messages/minute.

ConnectIQ watch faces use a **one-shot** `registerForPhoneAppMessageEvent` model:
1. Watch registers for a message
2. Phone delivers one message
3. Watch must process it, exit the background service, and re-register
4. This cycle takes 10-30 seconds of system overhead

At 6 messages/minute from Trio vs 2-3 messages/minute consumption capacity on the watch, the ConnectIQ message queue grew unbounded. Once the queue was deep, every message arrived 30+ minutes late because it had to wait behind all the queued messages.

### Fix

Changed the `.throttle()` interval from 10 seconds to 300 seconds (5 minutes), matching the CGM glucose reading interval:

```swift
watchStateSubject
    .throttle(for: .seconds(300), scheduler: DispatchQueue.main, latest: true)
    .sink { ... }
```

The watch's existing 5-minute poll (`Communications.transmit("status")`) bypasses the throttle entirely via `receivedMessage(_:from:)` calling `broadcastStateToWatchApps()` directly.

### Files Modified
- `GarminManager.swift` — changed throttle from 10s to 300s

---

## Attempt 7: Source Diagnostic Field (In Progress)

### Purpose

Added a `source` field to `GarminWatchState` to distinguish push vs poll messages on the watch debug display:
- `source = "push"` — proactive sends through the throttled Combine pipeline
- `source = "poll"` — immediate responses to watch "status" requests

This will reveal whether the 30-minute delay (if it persists) affects push messages, poll responses, or both.

### Files Modified
- `GarminWatchState.swift` — added `source: String?` field
- `GarminManager.swift` — set source="push" in buildWatchState, override to "poll" in receivedMessage

---

## Architecture: Before vs After

### Before (CoreData Fetch)

```
CGM Reading arrives
    → storeGlucoseBatch() writes to SQLite via NSBatchInsertRequest
    → glucoseStorage.updatePublisher fires
    → GarminManager.subscribeToUpdateTriggers() triggers
    → setupGarminWatchState() fetches from CoreData (STALE — batch insert bypassed PSC cache)
    → 10-second throttle on watchStateSubject
    → broadcastStateToWatchApps() → ConnectIQ sendMessage
    → Watch receives message 30+ minutes late (queue overflow from 10s throttle)
```

### After (LiveActivity Snapshot)

```
CGM Reading arrives
    → storeGlucoseInCoreData() saves to CoreData
    → LiveActivityManager's long-lived context auto-merges the save
    → pushCurrentContent() reads fresh data, publishes LiveActivitySnapshot
    → GarminManager receives snapshot (same data as Live Activity)
    → buildWatchState(from:) builds state synchronously (no CoreData fetch)
    → 300-second throttle on watchStateSubject (matches CGM interval)
    → broadcastStateToWatchApps() → ConnectIQ sendMessage
    → Watch also polls every 5 minutes (bypasses throttle)
```

### Key Differences

| Aspect | Before | After |
|---|---|---|
| Data source | Own CoreData fetch (backgroundContext) | LiveActivity snapshot (same as Lock Screen) |
| Freshness | Raced against writes; often stale | Always fresh (auto-merged context) |
| Push throttle | 10 seconds (6/min, overwhelmed watch) | 300 seconds (matches CGM interval) |
| Poll response | Went through throttle | Bypasses throttle (immediate) |
| DI scope | LiveActivityManager was .graph (per-resolve) | LiveActivityManager is .container (singleton) |

---

## Lessons Learned

1. **NSBatchInsertRequest is invisible to other contexts.** It writes directly to SQLite, bypassing the PSC row cache and `NSManagedObjectContextDidSave` notifications. Any context reading the same store will see stale data unless you explicitly call `mergeChanges(fromRemoteContextSave:into:)` with the inserted object IDs.

2. **Fresh contexts don't help with batch inserts.** Even a brand-new context goes through the same PSC, which has the same stale row cache. The staleness is at the persistent store level, not the context level.

3. **`automaticallyMergesChangesFromParent = true` is the reliable path.** Contexts created with this flag (via `newTaskContext()`) automatically pick up saves from other contexts. This is why the Live Activity always had fresh data.

4. **Swinject default scope (`.graph`) creates new instances per resolve.** If a service holds state (like a Combine publisher), it MUST be registered with `.inObjectScope(.container)` to ensure all consumers share the same instance. Without this, GarminManager subscribed to a publisher that nobody published to.

5. **ConnectIQ message delivery is not instant.** The one-shot `registerForPhoneAppMessageEvent` model means each message requires a full background service cycle. Sending messages faster than the watch can consume them creates an unbounded queue that never recovers.

6. **Don't add mergeChanges "for consistency."** The CarbsStorage mergeChanges addition (done alongside GlucoseStorage "for consistency") caused meals to disappear from History. Only add change propagation where it's actually needed.

7. **Guard ordering matters for publishers.** Placing `snapshotPublisher.send()` after a `guard let determination` meant Garmin got nothing when determination was nil. Always publish data for consumers that need partial data before guarding on fields only some consumers need.

---

## Files Modified (Complete List)

| File | Changes |
|---|---|
| `GlucoseStorage.swift` | Added mergeChanges after batch insert, debug logging |
| `CarbsStorage.swift` | Added then reverted mergeChanges (caused meal disappearance) |
| `GarminWatchState.swift` | Added glucoseDate, sentAt, source diagnostic fields |
| `GarminManager.swift` | Complete rewrite: removed CoreData fetches, wired to LiveActivity snapshot, 300s throttle, source field |
| `LiveActivityManager.swift` | Added LiveActivitySnapshot, snapshotPublisher, moved publish before determination guard |
| `DeterminationData.swift` | Added eventualBG, insulinSensitivity fields |
| `DataManager.swift` | Added eventualBG, insulinSensitivity to propertiesToFetch |
| `ServiceAssembly.swift` | Made LiveActivityManager a singleton (.inObjectScope(.container)) |

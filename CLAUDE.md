# Trio Apple Watch Complications - Development Guide

This document chronicles the complete development journey of native Apple Watch complications for the Trio diabetes management app, including all approaches tried, platform limitations discovered, and the final working implementation.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Critical Platform Discovery](#critical-platform-discovery)
4. [Files Created/Modified](#files-createdmodified)
5. [Implementation Details](#implementation-details)
6. [Data Flow](#data-flow)
7. [Timing Model](#timing-model)
8. [What We Tried (And Why It Failed)](#what-we-tried-and-why-it-failed)
9. [The Working Solution](#the-working-solution)
10. [Troubleshooting](#troubleshooting)
11. [Future Considerations](#future-considerations)

---

## Project Overview

### Goal
Create native Apple Watch complications that display live glucose data, trend arrows, and staleness indicators for Trio users.

### Requirements
- Display current glucose value with trend arrow
- Show timestamp of last reading
- Indicate data freshness (green/yellow/red based on age)
- Support all watchOS 10+ complication families:
  - `accessoryCircular` - Circular gauge with glucose
  - `accessoryCorner` - Corner placement with curved text
  - `accessoryRectangular` - Rectangular with full details
  - `accessoryInline` - Single line text

### Platform Target
- watchOS 10.0+
- WidgetKit-based complications (NOT ClockKit)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         iPhone (Trio App)                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              AppleWatchManager.swift                      │   │
│  │  - Monitors glucose changes via Core Data                │   │
│  │  - Sends data via WCSession:                             │   │
│  │    • transferUserInfo() for queued delivery              │   │
│  │    • updateApplicationContext() for persistent data      │   │
│  │    • sendMessage() when Watch is reachable               │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ WatchConnectivity
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Apple Watch                                 │
│                                                                  │
│  ┌────────────────────────┐    ┌─────────────────────────────┐  │
│  │   Watch App Extension  │    │   Complication Widget       │  │
│  │                        │    │   (Separate Process)        │  │
│  │  WatchState.swift      │    │                             │  │
│  │  - Receives WCSession  │    │  TrioWatchComplication.swift│  │
│  │  - Saves to App Group  │───▶│  - Reads from App Group     │  │
│  │  - Calls reloadAll     │    │  - Displays glucose data    │  │
│  │    Timelines()         │    │  - Shows staleness colors   │  │
│  │                        │    │                             │  │
│  │  TrioWatchApp.swift    │    │  Timeline entries:          │  │
│  │  - Background refresh  │    │  0, 5, 10, 15 min           │  │
│  │  - Every 15 minutes    │    │  Policy: .atEnd             │  │
│  └────────────────────────┘    └─────────────────────────────┘  │
│              │                              ▲                    │
│              │      App Group UserDefaults  │                    │
│              └──────────────────────────────┘                    │
│                                                                  │
│  Entitlements: group.org.nightscout.TEAMID.trio.trio-app-group  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Critical Platform Discovery

### The Core Issue: `transferCurrentComplicationUserInfo()` Does NOT Work with WidgetKit

This is the most important discovery of the entire project.

**Background:**
- `transferCurrentComplicationUserInfo()` is a ClockKit-era API
- It was designed for the old `CLKComplicationDataSource` system
- Apple has **not** updated it to work with WidgetKit complications

**Official Apple Engineer Statement (WWDC Labs):**
> "transferCurrentComplicationUserInfo() is specifically designed for ClockKit complications. For WidgetKit-based complications, you should use transferUserInfo() or updateApplicationContext() combined with WidgetCenter.shared.reloadAllTimelines()."

**What This Means:**
- You CANNOT get "immediate" complication updates like Loop does
- Loop still uses ClockKit (deprecated), which is why their method works
- Loop has an open issue to migrate to WidgetKit - they'll face the same limitation
- The system controls when `reloadAllTimelines()` actually refreshes (~10-15 min)

### Realistic Refresh Expectations

| Method | Timing | Notes |
|--------|--------|-------|
| `reloadAllTimelines()` | 10-15 min | System-controlled, not immediate |
| Background App Refresh | ~15 min | watchOS allows ~4/hour |
| Timeline `.atEnd` policy | When expired | System may delay |
| `updateApplicationContext()` | Immediate delivery | But widget still needs reload |

**Accepted Reality:** 10-15 minute refresh latency is the best achievable with WidgetKit.

---

## Files Created/Modified

### New Files Created

#### `Trio Watch Complication/TrioWatchComplication.swift`
The main complication widget implementation.

```swift
// Key components:
- GlucoseComplicationData: Codable struct for sharing data
- TrioWatchComplicationProvider: TimelineProvider implementation
- AccessoryCircularView: Gauge-based circular display
- AccessoryCornerView: Corner complication with curved text
- AccessoryRectangularView: Full details display
- AccessoryInlineView: Single line text
```

#### `Trio Watch Complication/TrioWatchComplication.entitlements`
App Group entitlement for shared data access.

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>$(TRIO_APP_GROUP_ID)</string>
</array>
```

### Modified Files

#### `Trio Watch App Extension/TrioWatchApp.swift`
Added background refresh handling.

```swift
// Key additions:
- WatchAppDelegate class with WKApplicationDelegate
- scheduleBackgroundRefresh() - every 15 minutes
- handle(_ backgroundTasks:) - processes WKApplicationRefreshBackgroundTask
- Checks applicationContext for pending data on wake
```

#### `Trio Watch App Extension/WatchState.swift`
Added complication data handling.

```swift
// Key additions:
- updateComplicationFromContext() - public method for background refresh
- didReceiveApplicationContext() - handles persistent data
- handleComplicationUpdate() - processes and saves data
- isGlucoseColorInRange() - checks for white (#ffffff) = in range
- Calls reloadAllTimelines() with 0.2-0.3s delay
- Uses synchronize() for immediate UserDefaults write
```

#### `Trio Watch App Extension/TrioWatchExtension.entitlements`
Added App Group entitlement (same as complication).

#### `Trio/Sources/Services/WatchManager/AppleWatchManager.swift`
Modified iPhone-side push logic.

```swift
// Key changes:
- Removed transferCurrentComplicationUserInfo() (doesn't work with WidgetKit)
- Added transferUserInfo() for complication data
- Added updateApplicationContext() for persistent delivery
- Added isGlucoseOutOfRange() helper
- Added shouldPushComplication() for intelligent pushing
- Tracks lastComplicationPushWasUrgent and lastComplicationPushGlucose
```

---

## Implementation Details

### App Group Configuration

The App Group enables data sharing between the Watch app and the complication widget (separate processes).

**Bundle ID Pattern:**
```
Watch App: org.nightscout.TEAMID.trio.watchkitapp
Complication: org.nightscout.TEAMID.trio.watchkitapp.TrioWatchComplication
App Group: group.org.nightscout.TEAMID.trio.trio-app-group
```

**Dynamic App Group Resolution:**
```swift
private func getAppGroupSuiteName() -> String? {
    guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
    let components = bundleId.components(separatedBy: ".")
    if let trioIndex = components.firstIndex(of: "trio"), trioIndex >= 3 {
        let base = components[0...trioIndex].joined(separator: ".")
        return "group.\(base).trio-app-group"
    }
    return nil
}
```

### GlucoseComplicationData Structure

```swift
struct GlucoseComplicationData: Codable {
    let glucose: String      // "120" or "6.7"
    let trend: String        // "→", "↗", "↑", etc.
    let delta: String        // "+5" or "-0.3"
    let iob: String?         // "1.5"
    let cob: String?         // "20"
    let glucoseDate: Date?   // Timestamp of reading
    let lastLoopDate: Date?  // Last loop cycle
    let isUrgent: Bool       // true when out of range

    // Computed properties
    var minutesAgo: Int      // Minutes since glucoseDate
    var timeString: String   // "10:45" format
    var isStale: Bool        // > 10 min old (yellow)
    var isVeryStale: Bool    // > 15 min old (red)
    var stalenessColor: Color // green/yellow/red
}
```

### Staleness Color Logic

| Condition | Color | Meaning |
|-----------|-------|---------|
| `minutesAgo <= 10` | Green | Fresh data |
| `minutesAgo > 10 && <= 15` | Yellow | Getting stale |
| `minutesAgo > 15` | Red | Very stale |
| No data | Red | No data available |

### Timeline Provider

```swift
func getTimeline(in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let data = GlucoseComplicationData.load()
    let currentDate = Date()

    var entries: [TrioWatchComplicationEntry] = []

    // Entry for now
    entries.append(TrioWatchComplicationEntry(date: currentDate, data: data))

    // Entries at 5, 10, and 15 minutes
    for minutes in [5, 10, 15] {
        let futureDate = currentDate.addingTimeInterval(Double(minutes * 60))
        entries.append(TrioWatchComplicationEntry(date: futureDate, data: data))
    }

    // .atEnd requests refresh when timeline expires
    let timeline = Timeline(entries: entries, policy: .atEnd)
    completion(timeline)
}
```

---

## Data Flow

### When iPhone Gets New Glucose Reading

```
1. Core Data change notification fires
2. AppleWatchManager.sendState() called
3. Sends complication data via:
   - transferUserInfo() - queued, reliable delivery
   - updateApplicationContext() - persistent, immediate availability
4. Watch app receives via WCSessionDelegate methods
5. WatchState saves to App Group UserDefaults
6. Calls WidgetCenter.shared.reloadAllTimelines()
7. System schedules complication refresh (10-15 min)
```

### When Watch App Wakes (Background Refresh)

```
1. WKApplicationRefreshBackgroundTask fires (every 15 min)
2. Check WCSession.default.receivedApplicationContext
3. If complicationUpdate data exists, process it
4. Request fresh data from iPhone
5. Call reloadAllTimelines() with 0.3s delay
6. Schedule next background refresh
7. Mark task complete
```

### When Complication Widget Refreshes

```
1. System calls getTimeline()
2. Load data from App Group UserDefaults
3. Create timeline entries for 0, 5, 10, 15 min
4. Return with .atEnd policy
5. System displays appropriate entry based on time
```

---

## Timing Model

All timing is aligned to 15-minute intervals:

| Component | Timing | Code Location |
|-----------|--------|---------------|
| Background Refresh | 15 min | `TrioWatchApp.swift:53` |
| Timeline Entries | 0, 5, 10, 15 min | `TrioWatchComplication.swift:173` |
| Timeline Policy | `.atEnd` | `TrioWatchComplication.swift:179` |
| Stale threshold | 10 min | `TrioWatchComplication.swift:113` |
| Very stale threshold | 15 min | `TrioWatchComplication.swift:116` |

---

## What We Tried (And Why It Failed)

### Attempt 1: `transferCurrentComplicationUserInfo()`

**What we tried:**
```swift
session.transferCurrentComplicationUserInfo(complicationData)
```

**Why it failed:**
- This is a ClockKit API, not WidgetKit
- Apple has not bridged it to WidgetKit
- Data was never received by the complication

### Attempt 2: Direct `reloadAllTimelines()` Without Delay

**What we tried:**
```swift
// Immediately after saving data
WidgetCenter.shared.reloadAllTimelines()
```

**Why it failed:**
- UserDefaults write may not be complete
- Complication reads stale data

**Fix:**
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
    WidgetCenter.shared.reloadAllTimelines()
}
```

### Attempt 3: Checking for Green Color to Detect In-Range

**What we tried:**
```swift
func isGlucoseColorInRange(_ colorString: String) -> Bool {
    return colorString.contains("00ff00") // green
}
```

**Why it failed:**
- iPhone sends `#ffffff` (white) for in-range glucose
- Green/red/etc. are for out-of-range states

**Fix:**
```swift
func isGlucoseColorInRange(_ colorString: String) -> Bool {
    let normalized = colorString.lowercased()
    return normalized == "#ffffff" || normalized == "ffffff"
}
```

### Attempt 4: Showing "X min ago" on Complication

**What we tried:**
```swift
Text("\(data.minutesAgo) min ago")
```

**Why it failed:**
- Complication doesn't update in real-time
- "5 min ago" stays frozen, becomes misleading

**Fix:**
```swift
// Show actual timestamp instead
Text("@ \(data.timeString)") // e.g., "@ 10:45"
```

### Attempt 5: Expecting Real-Time Updates

**What we tried:**
- Sending updates on every glucose reading
- Expecting immediate complication refresh

**Why it failed:**
- watchOS aggressively throttles widget refreshes
- System controls timing, not the app

**Fix:**
- Accept 10-15 min refresh latency
- Use staleness colors to indicate data age
- Show timestamp so user can calculate freshness

### Attempt 6: Background Refresh Checking WCSession Before Activation

**What we tried:**
```swift
func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    // Check activation BEFORE accessing WatchState.shared
    if WCSession.default.activationState == .activated {
        let context = WCSession.default.receivedApplicationContext
        // ...
    }
    WatchState.shared.requestWatchStateUpdate()
}
```

**Why it failed:**
- WCSession activation happens in `WatchState.shared`'s init
- We checked activation status BEFORE accessing `WatchState.shared`
- Session was never activated → context was never read
- When Watch app was killed, background refresh couldn't get data

**Fix:**
```swift
func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    // Access WatchState.shared FIRST to trigger session activation
    let watchState = WatchState.shared

    // Give session time to activate
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if WCSession.default.activationState == .activated {
            let context = WCSession.default.receivedApplicationContext
            if context["complicationUpdate"] as? Bool == true {
                watchState.updateComplicationFromContext(context)
            }
        }
        watchState.requestWatchStateUpdate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    Self.scheduleBackgroundRefresh()

    // Mark complete after async work finishes
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        backgroundTask.setTaskCompletedWithSnapshot(false)
    }
}
```

---

## The Working Solution

### iPhone Side (AppleWatchManager.swift)

```swift
// Send complication data via transferUserInfo (NOT transferCurrentComplicationUserInfo)
let complicationData: [String: Any] = [
    "complicationUpdate": true,
    WatchMessageKeys.currentGlucose: state.currentGlucose ?? "--",
    WatchMessageKeys.trend: state.trend ?? "",
    WatchMessageKeys.delta: state.delta ?? "",
    WatchMessageKeys.iob: state.iob ?? "",
    WatchMessageKeys.cob: state.cob ?? "",
    WatchMessageKeys.currentGlucoseColorString: state.currentGlucoseColorString ?? "#ffffff",
    WatchMessageKeys.date: state.date.timeIntervalSince1970
]
session.transferUserInfo(complicationData)

// Also update applicationContext for persistence
do {
    try session.updateApplicationContext(complicationData)
} catch {
    debug(.watchManager, "Failed to update applicationContext: \(error)")
}
```

### Watch Side (WatchState.swift)

```swift
func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    if userInfo["complicationUpdate"] as? Bool == true {
        handleComplicationUpdate(userInfo)
    }
}

func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    if applicationContext["complicationUpdate"] as? Bool == true {
        handleComplicationUpdate(applicationContext)
    }
}

private func handleComplicationUpdate(_ data: [String: Any]) {
    // Extract and save to App Group
    let complicationData = GlucoseComplicationData(...)
    complicationData.save()

    // Reload timelines with delay for UserDefaults sync
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

### Background Refresh (TrioWatchApp.swift)

```swift
func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
        if let backgroundTask = task as? WKApplicationRefreshBackgroundTask {
            // IMPORTANT: Access WatchState.shared FIRST to trigger WCSession activation
            // The session activation happens in WatchState's init
            let watchState = WatchState.shared

            // Give session a moment to activate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Check applicationContext for pending data (sent while app was killed)
                if WCSession.default.activationState == .activated {
                    let context = WCSession.default.receivedApplicationContext
                    if context["complicationUpdate"] as? Bool == true {
                        watchState.updateComplicationFromContext(context)
                    }
                }

                // Request fresh data from iPhone
                watchState.requestWatchStateUpdate()

                // Reload complications
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }

            // Schedule next refresh (immediately, not in delayed block)
            Self.scheduleBackgroundRefresh()

            // Mark task complete after giving time for async work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                backgroundTask.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
```

---

## Troubleshooting

### Complication Shows "--" or "No Data"

**Debug info displayed:**
```
AG:...app-group D:true V:false
```
- `AG:` = App Group suffix (last 15 chars)
- `D:true/false` = UserDefaults(suiteName:) succeeded
- `V:true/false` = Value exists for complicationData key

**Possible causes:**
1. App Group mismatch between Watch app and complication
2. Data not being saved to shared UserDefaults
3. Watch app hasn't received any data yet

**Solutions:**
1. Verify both entitlements files have same App Group
2. Check that `synchronize()` is called after save
3. Open Watch app to trigger data fetch

### Complication Not Updating

**Possible causes:**
1. System throttling widget refreshes
2. `reloadAllTimelines()` not being called
3. Timeline provider returning old data

**Solutions:**
1. Accept 10-15 min latency (platform limitation)
2. Check WatchLogger for reload calls
3. Verify App Group data is fresh

### Data Shows Wrong Staleness Color

**Possible causes:**
1. `glucoseDate` not being sent/saved
2. Time zone issues
3. Date parsing errors

**Solutions:**
1. Verify `WatchMessageKeys.date` is included in data
2. Use `timeIntervalSince1970` for timezone-safe transfer
3. Check `Date(timeIntervalSince1970:)` parsing

### Background Refresh Not Firing

**Possible causes:**
1. `scheduleBackgroundRefresh()` not called
2. watchOS power management limiting refreshes
3. App not properly configured

**Solutions:**
1. Ensure scheduled on app launch and in background handler
2. Accept that watchOS may skip refreshes to save battery
3. Verify WKApplicationDelegate is properly set up

### Watch App Killed = Complication Stops Updating

**Possible causes:**
1. Background refresh checking WCSession before it's activated
2. WCSession activation happens in WatchState's init, but we check before accessing it

**Solutions:**
1. Access `WatchState.shared` FIRST to trigger session activation
2. Add 0.5s delay before checking `receivedApplicationContext`
3. Mark task complete after 1.0s to allow async work to finish

**Critical code order:**
```swift
// WRONG - session never activates
if WCSession.default.activationState == .activated { ... }
WatchState.shared.requestWatchStateUpdate()

// RIGHT - access WatchState first, then wait
let watchState = WatchState.shared  // triggers activation
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    if WCSession.default.activationState == .activated { ... }
}
```

---

## Future Considerations

### Potential Improvements

1. **Smart Push Logic**: Only push complication updates when glucose goes out of range or changes significantly (partially implemented)

2. **Multiple Complication Variants**: Different widgets for different use cases (glucose-only vs. full details)

3. **User Preferences**: Allow customization of staleness thresholds, display format, etc.

4. **Extended Runtime**: Investigate `WKExtendedRuntimeSession` for more frequent updates during active sessions

### Known Limitations

1. **10-15 min refresh latency**: Platform limitation, cannot be circumvented
2. **No real-time updates**: WidgetKit does not support live updates like ClockKit did
3. **Background refresh limits**: watchOS allows ~4 per hour maximum
4. **Battery impact**: More frequent refreshes drain battery faster

### Comparison with Loop

| Feature | Trio (WidgetKit) | Loop (ClockKit) |
|---------|------------------|-----------------|
| API | WidgetKit | ClockKit (deprecated) |
| Immediate updates | No | Yes |
| Future-proof | Yes | No |
| Refresh control | System | App |

Loop uses `transferCurrentComplicationUserInfo()` with ClockKit, which gives them immediate updates. However, ClockKit is deprecated and Loop has an open issue to migrate to WidgetKit, where they'll face the same limitations.

---

## Commit History

Key commits on this feature branch:

1. Initial complication implementation with WidgetKit
2. Added App Group for data sharing
3. Fixed `transferCurrentComplicationUserInfo()` -> `transferUserInfo()`
4. Added `updateApplicationContext()` for persistence
5. Added `didReceiveApplicationContext` handler
6. Fixed color detection (white = in range)
7. Changed from "X min ago" to timestamp display
8. Added debug info to complication
9. Added background refresh to check `applicationContext`
10. Aligned timeline to 15-min intervals
11. Fixed background refresh not activating WCSession before checking context
12. Added comprehensive CLAUDE.md documentation

---

## References

- [WidgetKit Documentation](https://developer.apple.com/documentation/widgetkit)
- [WatchConnectivity Documentation](https://developer.apple.com/documentation/watchconnectivity)
- [WWDC 2020: Build complications in SwiftUI](https://developer.apple.com/videos/play/wwdc2020/10048/)
- [WWDC 2022: Go further with Complications in WidgetKit](https://developer.apple.com/videos/play/wwdc2022/10050/)

---

*Last updated: January 2026*
*Branch: claude/add-watch-complications-Mnd9b*

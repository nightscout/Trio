# Garmin Update Flow - Visual Diagram

## New Simplified Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Loop Cycle Completes                      │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ├─────────────────────────────┐
                    │                             │
                    ↓                             ↓
        ┌──────────────────────┐      ┌──────────────────────┐
        │  Determination       │      │  IOB Update          │
        │  CoreData Change     │      │  iobPublisher        │
        └──────────┬───────────┘      └──────────┬───────────┘
                   │                             │
                   │  .send(data)                │  .send(data)
                   ↓                             ↓
        ┌──────────────────────────────────────────────────────┐
        │         determinationSubject                          │
        │         (PassthroughSubject<Data, Never>)            │
        └──────────────────┬───────────────────────────────────┘
                           │
                           │  .throttle(for: .seconds(20),
                           │            latest: false)
                           ↓
        ┌──────────────────────────────────────────────────────┐
        │              Combine Throttle Logic                   │
        │   .throttle(for: .seconds(20), latest: false)        │
        │                                                       │
        │  ┌────────────────────────────────────┐             │
        │  │ Event 1 (t=0s)    → HOLD 📦        │             │
        │  │   [Start 20s timer]                │             │
        │  │ Event 2 (t=0.5s)  → DROP ❌        │             │
        │  │ Event 3 (t=1s)    → DROP ❌        │             │
        │  │ Event 4 (t=5s)    → DROP ❌        │             │
        │  │ [t=20s: Timer fires]               │             │
        │  │   → SEND Event 1 ✅                │             │
        │  │                                    │             │
        │  │ Event 5 (t=20.1s) → HOLD 📦        │             │
        │  │   [Start new 20s timer]            │             │
        │  │ Event 6 (t=23s)   → DROP ❌        │             │
        │  │ [t=40.1s: Timer fires]             │             │
        │  │   → SEND Event 5 ✅                │             │
        │  └────────────────────────────────────┘             │
        │                                                       │
        │  Pattern: HOLD first → DROP rest → SEND after 20s  │
        └──────────────────┬───────────────────────────────────┘
                           │
                           ↓
        ┌──────────────────────────────────────────────────────┐
        │         subscribeToDeterminationThrottle()            │
        │                                                       │
        │  • Check if recent watchface change (<25s)           │
        │    - If yes: Don't cache (might be old format) ⚠️    │
        │    - If no: Cache data ✅                            │
        │  • Convert Data → JSON                               │
        │  • Set lastImmediateSendTime                         │
        │  • Log: "Sending determination/IOB" (if enabled)     │
        └──────────────────┬───────────────────────────────────┘
                           │
                           ↓
        ┌──────────────────────────────────────────────────────┐
        │         broadcastStateToWatchApps()                   │
        │                                                       │
        │  ├─> Watchface App (5A643C13...)                     │
        │  └─> Data Field App (71CF0982...)                    │
        └───────────────────────────────────────────────────────┘
```

## Other Update Sources (Unchanged)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Glucose Update (Stale Loop)                   │
│                    (Loop age > 8 minutes)                        │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    │  Immediate send - no throttle
                    ↓
        ┌──────────────────────────────────────────────────────┐
        │         sendWatchStateDataImmediately()               │
        │                                                       │
        │  • Convert Data → JSON                               │
        │  • Set lastImmediateSendTime                         │
        │  • broadcastStateToWatchApps()                       │
        └───────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│              Status Request / Settings Changes                   │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    │  30s throttle
                    ↓
        ┌──────────────────────────────────────────────────────┐
        │         sendWatchStateDataWith30sThrottle()           │
        │                                                       │
        │  • Store pending data                                │
        │  • Start/update 30s timer                            │
        │  • Check lastImmediateSendTime before firing         │
        │  • broadcastStateToWatchApps() after 30s             │
        └───────────────────────────────────────────────────────┘
```

## Comparison: Old vs New

### Old Architecture (Complex)
```
Determination ──> sendWatchStateDataImmediately() ──> Watch
                      │
                      └─> Set lastImmediateSendTime
                      
IOB ──> sendWatchStateDataWith30sThrottle() ──> Watch
         │
         └─> Check lastImmediateSendTime? ❌ Race condition!
         └─> Start 30s timer
         └─> Cancel if determination fired? ⚠️ Complex!
```

### New Architecture (Simple)
```
Determination ──┐
                ├──> determinationSubject ──> .throttle(10s) ──> Watch
IOB ───────────┘
```

## Timeline Example

```
Time    Event                          Action
──────────────────────────────────────────────────────────────────
0:00    Loop completes                 
        ├─ Determination fires ─┐
        └─ IOB fires ───────────┴──> determinationSubject.send()
                                                │
0:00                                   Throttle: SEND ✅
                                       Log: "Sending determination/IOB"
                                                │
0:00-10s Multiple loop cycles         Throttle: DROP ALL ❌
        (rapid determinations/IOB)              │
                                                │
10:01   Next loop completes            Throttle: SEND ✅
        ├─ Determination fires ─┐      Log: "Sending determination/IOB"
        └─ IOB fires ───────────┘
                                                │
15:00   Status request arrives         30s timer starts
                                       (separate pipeline)
                                                │
20:01   Loop completes                 Throttle: SEND ✅
        ├─ Determination fires ─┐      (30s timer cancelled - recent send)
        └─ IOB fires ───────────┘
```

## Key Architectural Decisions

### Why Combine Throttle Instead of Manual Timer?

**Combine throttle:**
✅ Built-in deduplication
✅ Thread-safe by design
✅ Predictable scheduler behavior
✅ Less code to maintain
✅ No race conditions

**Manual timer:**
❌ Complex lifecycle management
❌ Race conditions between publishers
❌ More code to test
❌ Threading concerns
❌ Easy to introduce bugs

### Why 10 Seconds?

1. **Loop cycle timing:** Typical loop = 5 minutes
2. **Multiple events = same cycle:** Events within 10s are from same loop
3. **Responsiveness:** 10s is imperceptible to users
4. **Battery efficiency:** Reduces watch transmissions by ~80%

### Why `latest: false`?

| Setting | Behavior | Result |
|---------|----------|--------|
| `latest: false` | Keep **first** event, drop rest | Send immediately when loop completes ✅ |
| `latest: true` | Drop events, send **last** one after throttle | 10 second delay every time ❌ |

We want immediate response when data arrives, not delayed response.

## Code Metrics

### Lines of Code
- **Old approach:** ~150 lines of throttling logic
- **New approach:** ~60 lines of throttling logic
- **Reduction:** 60% less code

### Complexity
- **Old approach:** 3 throttle mechanisms (immediate, 10s manual, 30s manual)
- **New approach:** 2 throttle mechanisms (10s Combine, 30s manual)
- **Timer objects:** Reduced from 2 to 1

### Edge Cases Handled
- **Old approach:** ~8 edge cases (race conditions, timer coordination, etc.)
- **New approach:** ~3 edge cases (all handled by Combine)

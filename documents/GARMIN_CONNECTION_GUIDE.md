# Trio Garmin Watch Connection Guide

This document describes how Trio communicates with Garmin watchface and data field apps, the data format used, and what a new custom Garmin app needs to do to receive data from Trio.

---

## Architecture Overview

Trio uses the **Garmin ConnectIQ Mobile SDK** (iOS) to send real-time loop data to Garmin watch apps. The communication flow is:

```
Trio iOS App
    |
    |  (ConnectIQ SDK - Bluetooth via Garmin Connect Mobile)
    v
Garmin Connect Mobile (bridge app on iPhone)
    |
    |  (Bluetooth Low Energy)
    v
Garmin Watch App (watchface or data field)
```

There are two types of watch apps that Trio communicates with:

| App Type    | Current UUID                             | Description                          |
|-------------|------------------------------------------|--------------------------------------|
| Watchface   | `EC3420F6-027D-49B3-B45F-D81D6D3ED90A`  | Full watchface showing loop data     |
| Data Field  | `71CF0982-CA41-42A5-8441-EA81D36056C3`  | Data field overlay for activity apps |

Each app is identified by a UUID. When you create a new Garmin app, it will have its own unique UUID assigned by the ConnectIQ developer portal.

---

## Prerequisites

For the Trio-to-Garmin connection to work, the following must be in place:

1. **Garmin Connect Mobile** must be installed on the iPhone (Trio checks this and alerts the user if missing)
2. **ConnectIQ SDK** is linked into Trio (framework: `ConnectIQ`)
3. The Trio app registers a **custom URL scheme** (`Trio`) so that Garmin Connect Mobile can redirect back to Trio after device selection
4. The Garmin watch app (watchface or data field) must be installed on the watch via the Connect IQ store or sideloaded

---

## Device Pairing Flow

### How Devices Get Paired

1. User taps "Add Device" in Trio's settings (Settings > Watch Configuration > Garmin)
2. Trio calls `ConnectIQ.sharedInstance().showDeviceSelection()` which opens Garmin Connect Mobile
3. User selects their watch in Garmin Connect Mobile
4. Garmin Connect Mobile redirects back to Trio via URL scheme: `Trio://device-select-resp?...`
5. Trio's `handleURL()` method catches this and posts an `.openFromGarminConnect` notification
6. `GarminManager` parses the device info from the URL via `connectIQ.parseDeviceSelectionResponse(from: url)`
7. Devices are persisted to `UserDefaults` (key: `BaseGarminManager.persistedDevices`) as `GarminDevice` objects (UUID, model name, friendly name)
8. On subsequent app launches, devices are automatically restored from persistence

### Device Registration

Once devices are known, Trio registers for:
- **Device events** (`IQDeviceEventDelegate`) — tracks connected/disconnected/not-found status
- **App messages** (`IQAppMessageDelegate`) — receives messages from the watch apps (e.g., status requests)

For each device, Trio creates two `IQApp` instances (one per UUID — watchface and data field) and stores them in a `watchApps` array for message dispatch.

---

## Data Sent to Watch

### GarminWatchState Structure

Trio sends a JSON-encoded dictionary with these fields:

| Field                  | Type     | Description                                                        | Example Value    |
|------------------------|----------|--------------------------------------------------------------------|------------------|
| `glucose`              | String?  | Current glucose reading, formatted per user's unit preference      | `"120"` or `"6.7"` |
| `trendRaw`             | String?  | Glucose trend direction string                                     | `"Flat"`, `"FortyFiveUp"`, `"SingleUp"` |
| `delta`                | String?  | Change from previous reading, with +/- prefix                      | `"+5"`, `"-3"`, `"+0.3"` |
| `iob`                  | String?  | Insulin on board, 1 decimal place                                  | `"2.5"`, `"0.1"` |
| `cob`                  | String?  | Carbs on board, integer                                            | `"25"`, `"0"`    |
| `lastLoopDateInterval` | UInt64?  | Unix epoch timestamp (seconds) of last successful loop             | `1706123456`     |
| `eventualBGRaw`        | String?  | Predicted eventual blood glucose                                   | `"135"` or `"7.5"` |
| `isf`                  | String?  | Current insulin sensitivity factor                                 | `"40"` or `"2.2"` |

### Important Notes on Data Format

- **All numeric values are sent as strings** (not numbers), except `lastLoopDateInterval` which is a UInt64
- **Glucose units** are pre-formatted by Trio based on the user's preference (mg/dL or mmol/L). The watch receives values already in the correct unit
- **Delta** includes a `+` prefix for positive values and a `-` for negative values (the `-` comes from the number itself)
- **IOB** uses `.` as decimal separator regardless of locale, with exactly 1 fraction digit. Values smaller than 0.1 (but non-zero) are clamped to `"0.1"` or `"-0.1"`
- **Trend direction values** come from the CGM sensor. Common values include:
  - `"Flat"` — stable
  - `"FortyFiveUp"` / `"FortyFiveDown"` — slowly rising/falling
  - `"SingleUp"` / `"SingleDown"` — rising/falling
  - `"DoubleUp"` / `"DoubleDown"` — rapidly rising/falling
  - `"--"` — unknown/unavailable

### JSON Example

A typical message sent to the watch looks like:

```json
{
  "glucose": "120",
  "trendRaw": "Flat",
  "delta": "+5",
  "iob": "2.5",
  "cob": "25",
  "lastLoopDateInterval": 1706123456,
  "eventualBGRaw": "135",
  "isf": "40"
}
```

Fields that have no data available will be `null` (absent from the dictionary).

---

## When Updates Are Sent

Trio rebuilds and sends the watch state when any of these events occur:

| Trigger                        | Source                                              |
|--------------------------------|-----------------------------------------------------|
| New glucose reading arrives    | `glucoseStorage.updatePublisher`                    |
| IOB value changes              | `iobService.iobPublisher`                           |
| New loop determination         | CoreData save notification for `OrefDetermination`  |
| Glucose entry deleted          | CoreData change notification for `GlucoseStored`    |
| User changes glucose units     | `SettingsObserver` callback                         |
| Watch requests an update       | Watch sends `"status"` message to Trio              |

### Throttling

All updates are throttled to a **minimum 10-second interval** via Combine's `.throttle()` operator. If multiple triggers fire within 10 seconds, only the most recent state is sent. This prevents overwhelming the Bluetooth connection.

---

## Message Transport Protocol

### Trio to Watch (Push)

1. `GarminWatchState` is created with the latest data
2. Encoded to JSON via `JSONEncoder().encode(watchState)`
3. Deserialized to `NSDictionary` via `JSONSerialization.jsonObject()`
4. Published through a `PassthroughSubject<NSDictionary, Never>` (throttled at 10s)
5. For each app in `watchApps`, Trio checks if the app is installed via `connectIQ.getAppStatus()`
6. If installed, sends via `connectIQ.sendMessage(dict, to: app, progress:, completion:)`
7. The ConnectIQ SDK handles the Bluetooth transport through Garmin Connect Mobile to the watch

### Watch to Trio (Pull)

The watch can request an update by sending the string `"status"` to Trio:

1. Watch app calls `Communications.transmit("status", ...)` (Monkey C side)
2. Trio receives this in `receivedMessage(_:from:)` delegate method
3. Trio checks if the message equals the string `"status"`
4. If so, Trio rebuilds the full watch state and sends it back through the same push mechanism

This pull mechanism is useful when the watch app first starts up or reconnects after being out of range.

---

## What a New Garmin App Needs to Do

### 1. Create a ConnectIQ App Project

- Register as a Garmin developer at [developer.garmin.com](https://developer.garmin.com)
- Create a new ConnectIQ project using the Garmin SDK (Monkey C language)
- Choose the project type: **Watch Face** or **Data Field** (or both)
- Your app will receive a unique **App UUID** from the ConnectIQ developer portal

### 2. Implement Communications in Monkey C

Your Garmin app needs to use the `Communications` module to receive data from Trio.

#### Register a Communications Listener

```monkeyc
using Toybox.Communications;

// In your App or View class:
function onStart(state) {
    // Register to receive messages from the phone
    Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
}

function onPhoneMessage(msg) {
    // msg.data is a Dictionary with the fields from GarminWatchState
    var data = msg.data;

    var glucose = data["glucose"];           // String or null
    var trend = data["trendRaw"];            // String or null
    var delta = data["delta"];               // String or null
    var iob = data["iob"];                   // String or null
    var cob = data["cob"];                   // String or null
    var loopTime = data["lastLoopDateInterval"]; // Number (epoch seconds) or null
    var eventualBG = data["eventualBGRaw"];  // String or null
    var isf = data["isf"];                   // String or null

    // Update your display with this data
    // Call WatchUi.requestUpdate() to trigger onUpdate()
    WatchUi.requestUpdate();
}
```

#### Request Data from Trio (Optional Pull)

If your app needs to request fresh data (e.g., on startup):

```monkeyc
function requestUpdate() {
    Communications.transmit("status", null, new StatusListener());
}

class StatusListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }
    function onComplete() {
        // Message sent successfully, Trio will respond with data
    }
    function onError() {
        // Handle error
    }
}
```

### 3. Register Your App UUID in Trio

For Trio to send data to your new app, its UUID must be registered in Trio's `GarminManager`. The current UUIDs are defined in:

**File:** `Trio/Sources/Services/WatchManager/GarminManager.swift` (lines 621-627)

```swift
private enum Config {
    static let watchfaceUUID = UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")
    static let watchdataUUID = UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
}
```

To add your new app, you have two options:

#### Option A: Replace an Existing UUID

If you are replacing the existing watchface or data field, update the corresponding UUID:

```swift
private enum Config {
    static let watchfaceUUID = UUID(uuidString: "YOUR-NEW-WATCHFACE-UUID")
    static let watchdataUUID = UUID(uuidString: "YOUR-NEW-DATAFIELD-UUID")
}
```

#### Option B: Add Additional App UUIDs

If you want to support your new apps alongside the existing ones, add new UUID constants and register them in `registerDevices()`:

```swift
private enum Config {
    static let watchfaceUUID = UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")
    static let watchdataUUID = UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
    static let customWatchfaceUUID = UUID(uuidString: "YOUR-CUSTOM-WATCHFACE-UUID")
    static let customDataFieldUUID = UUID(uuidString: "YOUR-CUSTOM-DATAFIELD-UUID")
}
```

Then in `registerDevices()`, create and register `IQApp` instances for the new UUIDs, following the same pattern used for the existing apps (lines 361-393).

### 4. Handle the Data on the Watch

Your watch app should:

1. **Parse the dictionary** — All values are strings except `lastLoopDateInterval` (number). Handle `null` values gracefully
2. **Display glucose** — The value is already formatted in the user's preferred unit (mg/dL or mmol/L)
3. **Map trend arrows** — Convert `trendRaw` strings to arrow symbols or graphics:
   - `"DoubleUp"` → rapid rise (e.g., double arrow up)
   - `"SingleUp"` → rising
   - `"FortyFiveUp"` → slowly rising (diagonal arrow)
   - `"Flat"` → stable (horizontal arrow)
   - `"FortyFiveDown"` → slowly falling
   - `"SingleDown"` → falling
   - `"DoubleDown"` → rapid fall
   - `"--"` or `null` → unknown
4. **Calculate loop staleness** — Compare `lastLoopDateInterval` (epoch seconds) to current time to determine how long ago the last loop ran. Display a warning if stale (e.g., > 15 minutes)
5. **Handle missing data** — Any field can be `null`. Display placeholder text (e.g., `"--"`) when data is unavailable
6. **Request updates on start** — Send `"status"` to Trio when your app starts so you get immediate data without waiting for the next push cycle

### 5. Testing

- Install Garmin Connect Mobile on your iPhone
- Use the ConnectIQ simulator or sideload your app to a physical watch
- Pair the watch in Trio (Settings > Watch Configuration > Garmin > Add Device)
- Verify data appears on your watch and updates when glucose readings arrive

---

## Key Source Files Reference

| File | Purpose |
|------|---------|
| `Trio/Sources/Services/WatchManager/GarminManager.swift` | Main manager: device registration, data assembly, message dispatch |
| `Trio/Sources/Models/GarminWatchState.swift` | Data model for the watch state payload |
| `Trio/Sources/Models/GarminDevice.swift` | Codable wrapper for persisting IQDevice |
| `Trio/Sources/Modules/WatchConfig/View/WatchConfigGarminView.swift` | UI for adding/removing Garmin devices |
| `Trio/Sources/Application/TrioApp.swift` (line 459) | URL handler for `Trio://device-select-resp` callback |
| `Trio/Sources/Assemblies/ServiceAssembly.swift` (line 24) | Swinject registration of GarminManager |
| `Config.xcconfig` | Defines `APP_URL_SCHEME = Trio` |
| `Trio/Resources/Info.plist` (line 38) | Registers the `Trio` URL scheme with iOS |

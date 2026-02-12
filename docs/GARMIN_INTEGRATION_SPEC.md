# Garmin Integration Specification

Complete specification of the Garmin integration in Trio, covering two independent subsystems:

1. **Garmin Health Data (Firestore)** — Fetches sleep, stress, HRV, activity, and body battery data from a user-owned Firebase/Firestore database (populated by a Cloud Function that receives Garmin Health API webhooks). This data feeds a rule-based sensitivity model that adjusts insulin demand.

2. **Garmin Watch Communication (ConnectIQ)** — Sends real-time glucose, IOB, COB, trend, and loop status to a Garmin watch face/data field via the ConnectIQ SDK.

These two systems share the `garminEnabled` setting but are otherwise independent — the watch communication does not depend on Firestore, and the sensitivity model does not depend on the watch.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Build-Time Secret Injection](#2-build-time-secret-injection)
3. [Firebase Authentication Flow](#3-firebase-authentication-flow)
4. [Firestore Data Structure & Queries](#4-firestore-data-structure--queries)
5. [Data Model: GarminContextSnapshot](#5-data-model-garmincontextsnapshot)
6. [Sensitivity Model: GarminSensitivityModel](#6-sensitivity-model-garminsensitivitymodel)
7. [Integration Points: Where Demand Factor Is Used](#7-integration-points-where-demand-factor-is-used)
8. [ConnectIQ Watch Communication](#8-connectiq-watch-communication)
9. [Data Model: GarminWatchState](#9-data-model-garminwatchstate)
10. [Data Model: GarminDevice](#10-data-model-garmindevice)
11. [Settings & UI](#11-settings--ui)
12. [File Inventory](#12-file-inventory)
13. [External Dependencies](#13-external-dependencies)

---

## 1. Architecture Overview

```
Garmin Health API Webhooks
        │
        ▼
Cloud Function (user-deployed)
        │
        ▼
Firebase Firestore  ◄──── GarminFirestoreService (queries)
        │                         │
        │                         ▼
        │               GarminContextSnapshot (~40 health fields)
        │                         │
        │                         ▼
        │               GarminSensitivityModel.computeDemandFactor()
        │                         │
        │                         ▼
        │               insulinDemandFactor (0.70 – 1.30)
        │                         │
        │           ┌─────────────┼─────────────┐
        │           ▼             ▼             ▼
        │     CarbsStorage   Treatments    V2Outcome
        │     (engine runs)  (UI display)  (export)
        │
        ╳  (no connection)
        │
Garmin Watch ◄──── GarminManager (ConnectIQ SDK)
                        │
                        ▼
                   GarminWatchState (glucose, IOB, COB, trend, ISF, eventual BG)
```

---

## 2. Build-Time Secret Injection

**File: `Trio/Sources/Services/Garmin/GarminFirebaseConfig.swift`**

Secrets are injected by GitHub Actions at build time. Placeholder values (`__GARMIN_FIREBASE_*__`) are replaced via `sed` in the CI workflow. If secrets are not configured, `isConfigured` returns `false` and the entire Firestore subsystem gracefully disables itself.

```swift
import Foundation

// MARK: - Garmin Firebase Configuration
//
// This file holds the Firebase project configuration for the user's Garmin Firestore database.
// Values are injected at build time by GitHub Actions from repository secrets.
//
// To configure: Add these GitHub secrets to your repository:
//   GARMIN_FIREBASE_API_KEY          - Firebase Web API Key
//   GARMIN_FIREBASE_PROJECT_ID       - Firebase Project ID
//   GARMIN_FIREBASE_GCM_SENDER_ID    - GCM Sender ID (number)
//   GARMIN_FIREBASE_GOOGLE_APP_ID    - Google App ID (1:xxxxx:ios:xxxxx)
//   GARMIN_FIREBASE_STORAGE_BUCKET   - Firebase Storage Bucket
//   GARMIN_FIREBASE_USER_ID          - Your Firestore user UID
//   GARMIN_FIREBASE_EMAIL            - Firebase Auth email
//   GARMIN_FIREBASE_PASSWORD         - Firebase Auth password
//
// The build workflow replaces the placeholder values below before compilation.
// If secrets are not configured, Garmin Firestore integration is gracefully disabled.

enum GarminFirebaseConstants {
    // Firebase project config — replaced at build time by GitHub Actions
    static let apiKey = "__GARMIN_FIREBASE_API_KEY__"
    static let projectID = "__GARMIN_FIREBASE_PROJECT_ID__"
    static let gcmSenderID = "__GARMIN_FIREBASE_GCM_SENDER_ID__"
    static let googleAppID = "__GARMIN_FIREBASE_GOOGLE_APP_ID__"
    static let storageBucket = "__GARMIN_FIREBASE_STORAGE_BUCKET__"

    // Firestore user identity
    static let firestoreUserID = "__GARMIN_FIREBASE_USER_ID__"

    // Firebase Auth credentials (email/password)
    static let authEmail = "__GARMIN_FIREBASE_EMAIL__"
    static let authPassword = "__GARMIN_FIREBASE_PASSWORD__"

    /// Returns true if the build-time secrets were injected (i.e., not still placeholder values).
    static var isConfigured: Bool {
        !apiKey.hasPrefix("__") && !projectID.hasPrefix("__") && !googleAppID.hasPrefix("__")
    }
}
```

**GitHub Secrets Required:**

| Secret Name | Example Value | Purpose |
|---|---|---|
| `GARMIN_FIREBASE_API_KEY` | `AIzaSy...` | Firebase Web API Key |
| `GARMIN_FIREBASE_PROJECT_ID` | `my-garmin-project` | Firebase Project ID |
| `GARMIN_FIREBASE_GCM_SENDER_ID` | `123456789` | GCM Sender ID |
| `GARMIN_FIREBASE_GOOGLE_APP_ID` | `1:123:ios:abc` | Google App ID |
| `GARMIN_FIREBASE_STORAGE_BUCKET` | `my-garmin-project.appspot.com` | Firebase Storage Bucket |
| `GARMIN_FIREBASE_USER_ID` | `0Zp7LAT9bLMIEFWNyy694Gylf0n1` | Firestore user document UID |
| `GARMIN_FIREBASE_EMAIL` | `user@example.com` | Firebase Auth email |
| `GARMIN_FIREBASE_PASSWORD` | `secretpass` | Firebase Auth password |

---

## 3. Firebase Authentication Flow

**File: `Trio/Sources/Services/Garmin/GarminFirestoreService.swift`** (lines 60–118)

Trio's main Firebase app is used for Crashlytics. Garmin uses a **separate, named Firebase app** (`"garmin"`) to avoid conflicts. Authentication uses email/password sign-in.

```swift
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Manages the secondary Firebase app instance for the user's Garmin Firestore project.
/// The default FirebaseApp is used by Trio for Crashlytics. This creates a separate
/// named app ("garmin") for accessing the user's personal Firestore.
enum GarminFirebaseManager {
    private static let appName = "garmin"
    private(set) static var isSignedIn = false

    /// Configure the secondary Firebase app and sign in.
    /// Safe to call multiple times — skips if already configured.
    static func configureAndSignIn() async {
        guard GarminFirebaseConstants.isConfigured else {
            debug(.service, "Garmin Firebase: not configured (secrets not injected)")
            return
        }

        // Configure the secondary Firebase app if not already done
        if FirebaseApp.app(name: appName) == nil {
            let options = FirebaseOptions(
                googleAppID: GarminFirebaseConstants.googleAppID,
                gcmSenderID: GarminFirebaseConstants.gcmSenderID
            )
            options.apiKey = GarminFirebaseConstants.apiKey
            options.projectID = GarminFirebaseConstants.projectID
            options.storageBucket = GarminFirebaseConstants.storageBucket

            FirebaseApp.configure(name: appName, options: options)
            debug(.service, "Garmin Firebase: secondary app configured (project: \(GarminFirebaseConstants.projectID))")
        }

        // Sign in if not already authenticated
        guard let app = FirebaseApp.app(name: appName) else { return }
        let auth = Auth.auth(app: app)

        if auth.currentUser != nil {
            isSignedIn = true
            debug(.service, "Garmin Firebase: already signed in as \(auth.currentUser?.uid ?? "unknown")")
            return
        }

        do {
            let result = try await auth.signIn(
                withEmail: GarminFirebaseConstants.authEmail,
                password: GarminFirebaseConstants.authPassword
            )
            isSignedIn = true
            debug(.service, "Garmin Firebase: signed in as \(result.user.uid)")
        } catch {
            isSignedIn = false
            debug(.service, "Garmin Firebase: sign-in failed — \(error.localizedDescription)")
        }
    }

    /// Get the Firestore instance for the Garmin Firebase app.
    /// Returns nil if not configured or not signed in.
    static var firestore: Firestore? {
        guard isSignedIn, let app = FirebaseApp.app(name: appName) else { return nil }
        return Firestore.firestore(app: app)
    }
}
```

**Authentication sequence:**
1. Check `GarminFirebaseConstants.isConfigured` — if placeholders still present, bail
2. Create a named `FirebaseApp` (`"garmin"`) with the user's project credentials if not already created
3. Get `Auth.auth(app:)` for that named app
4. If already signed in (`currentUser != nil`), skip
5. Otherwise, `auth.signIn(withEmail:password:)` using the build-time injected credentials
6. Set `isSignedIn` flag — all downstream code checks this before querying Firestore

---

## 4. Firestore Data Structure & Queries

**File: `Trio/Sources/Services/Garmin/GarminFirestoreService.swift`** (lines 26–390)

### 4.1 Firestore Document Tree

```
users/{uid}/garminData/
  ├── dailySummaries/
  │   └── dates/
  │       ├── 2025-01-15   (document)
  │       ├── 2025-01-16   (document)
  │       └── ...
  ├── sleep/
  │   └── dates/
  │       ├── 2025-01-15
  │       └── ...
  ├── stressDetails/
  │   └── dates/
  │       ├── 2025-01-15
  │       └── ...
  ├── hrv/
  │   └── dates/
  │       ├── 2025-01-15
  │       └── ...
  └── userMetrics/
      └── dates/
          ├── 2025-01-15
          └── ...
```

Path pattern: `/users/{uid}/garminData/{dataType}/dates/{YYYY-MM-DD}`

The Cloud Function transforms raw Garmin Health API field names to shorter Firestore field names (e.g., `restingHeartRateInBeatsPerMinute` -> `restingHeartRate`, durations stored in minutes not seconds).

### 4.2 Configuration

```swift
struct GarminFirestoreConfig: Codable {
    var isEnabled: Bool = false
    var userID: String = ""  // Firestore user ID: e.g. "0Zp7LAT9bLMIEFWNyy694Gylf0n1"

    /// Base path: /users/{userID}/garminData
    var basePath: String { "users/\(userID)/garminData" }

    /// Data type document names under garminData/.
    var dailySummariesType: String = "dailySummaries"
    var sleepType: String = "sleep"
    var stressDetailsType: String = "stressDetails"
    var hrvType: String = "hrv"
    var userMetricsType: String = "userMetrics"

    /// Subcollection name under each data type document.
    var dateSubcollection: String = "dates"

    /// Cache duration — don't re-query within this interval (seconds)
    var cacheDurationSeconds: TimeInterval = 5 * 60 // 5 minutes
}
```

### 4.3 Service Protocol and Implementation

```swift
protocol GarminFirestoreServiceProtocol {
    func fetchContext() async -> GarminContextSnapshot?
    var isConfigured: Bool { get }
}

final class GarminFirestoreService: GarminFirestoreServiceProtocol {

    private var cachedSnapshot: GarminContextSnapshot?
    private var cacheTimestamp: Date?
    private let config: GarminFirestoreConfig

    var isConfigured: Bool {
        config.isEnabled && !config.userID.isEmpty && GarminFirebaseManager.isSignedIn
    }

    init(config: GarminFirestoreConfig = GarminFirestoreConfig()) {
        self.config = config
    }

    /// Convenience initializer that builds config from GarminFirebaseConstants.
    convenience init() {
        let config = GarminFirestoreConfig(
            isEnabled: GarminFirebaseConstants.isConfigured,
            userID: GarminFirebaseConstants.firestoreUserID
        )
        self.init(config: config)
    }

    /// Fetch the latest Garmin context snapshot from Firestore.
    /// Returns nil if Firestore is unavailable, the query fails, or Garmin is not configured.
    func fetchContext() async -> GarminContextSnapshot? {
        guard isConfigured else { return nil }

        // Check cache
        if let cached = cachedSnapshot,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < config.cacheDurationSeconds
        {
            return cached
        }

        // Build snapshot from Firestore documents
        let snapshot = await buildSnapshot()
        if snapshot != nil {
            cachedSnapshot = snapshot
            cacheTimestamp = Date()
        }
        return snapshot
    }
```

### 4.4 Building the Snapshot (Parallel Firestore Queries)

All queries run in parallel using `async let`:

```swift
    private func buildSnapshot() async -> GarminContextSnapshot? {
        let today = calendarDateString(for: Date())
        let yesterday = calendarDateString(for: Date().addingTimeInterval(-86400))

        // Fetch documents in parallel
        async let dailyToday = fetchDocument(dataType: config.dailySummariesType, documentID: today)
        async let dailyYesterday = fetchDocument(dataType: config.dailySummariesType, documentID: yesterday)
        async let sleepToday = fetchMostRecentDocument(dataType: config.sleepType, onOrBefore: today)
        async let stressToday = fetchDocument(dataType: config.stressDetailsType, documentID: today)
        async let hrvToday = fetchMostRecentDocument(dataType: config.hrvType, onOrBefore: today)
        async let userMetrics = fetchMostRecentDocument(dataType: config.userMetricsType, onOrBefore: today)

        // Also fetch last 7 days of dailies and HRV for computing averages
        async let dailies7Day = fetchDocuments(dataType: config.dailySummariesType, lastDays: 7)
        async let hrv7Day = fetchDocuments(dataType: config.hrvType, lastDays: 7)

        let (daily, yDaily, sleep, stress, hrv, metrics, recentDailies, recentHRV) = await (
            dailyToday, dailyYesterday, sleepToday, stressToday, hrvToday, userMetrics, dailies7Day, hrv7Day
        )

        // If we got no data at all, return nil
        guard daily != nil || sleep != nil || stress != nil || hrv != nil else { return nil }

        // Extract body battery and stress from stressDetails timelines
        let (currentBB, wakeBB) = extractBodyBattery(from: stress)
        let currentStress = extractCurrentStress(from: stress)

        // Compute 7-day averages
        let avgRHR = compute7DayAvgRHR(from: recentDailies)
        let avgHRV = compute7DayAvgHRV(from: recentHRV)

        return GarminContextSnapshot(
            queryTime: Date(),
            // Daily Summary — Firestore fields mapped to internal model
            restingHeartRateInBeatsPerMinute: daily?["restingHeartRate"] as? Int,
            averageHeartRateInBeatsPerMinute: daily?["averageHeartRate"] as? Int,
            averageStressLevel: daily?["stressAverage"] as? Int,
            maxStressLevel: daily?["stressMax"] as? Int,
            stressDurationInSeconds: daily?["stressDurationSeconds"] as? Int,
            restStressDurationInSeconds: daily?["restStressDurationSeconds"] as? Int,
            lowStressDurationInSeconds: daily?["lowStressDurationSeconds"] as? Int,
            mediumStressDurationInSeconds: daily?["mediumStressDurationSeconds"] as? Int,
            highStressDurationInSeconds: daily?["highStressDurationSeconds"] as? Int,
            stressQualifier: daily?["stressQualifier"] as? String,
            steps: daily?["steps"] as? Int,
            activeKilocalories: daily?["activeCalories"] as? Int,
            moderateIntensityDurationInSeconds: daily?["moderateIntensitySeconds"] as? Int,
            vigorousIntensityDurationInSeconds: daily?["vigorousIntensitySeconds"] as? Int,
            bodyBatteryChargedValue: daily?["bodyBatteryCharged"] as? Int,
            bodyBatteryDrainedValue: daily?["bodyBatteryDrained"] as? Int,
            // Yesterday's Daily
            yesterdaySteps: yDaily?["steps"] as? Int,
            yesterdayActiveKilocalories: yDaily?["activeCalories"] as? Int,
            yesterdayModerateIntensityDurationInSeconds: yDaily?["moderateIntensitySeconds"] as? Int,
            yesterdayVigorousIntensityDurationInSeconds: yDaily?["vigorousIntensitySeconds"] as? Int,
            // Sleep — Firestore stores durations in minutes; convert to seconds for internal model
            sleepDurationInSeconds: minutesToSeconds(sleep?["totalMinutes"] as? Int),
            deepSleepDurationInSeconds: minutesToSeconds(sleep?["deepSleepMinutes"] as? Int),
            lightSleepDurationInSeconds: minutesToSeconds(sleep?["lightSleepMinutes"] as? Int),
            remSleepInSeconds: minutesToSeconds(sleep?["remSleepMinutes"] as? Int),
            awakeDurationInSeconds: minutesToSeconds(sleep?["awakeMinutes"] as? Int),
            sleepScoreValue: sleep?["garminSleepScore"] as? Int,
            sleepScoreQualifier: nil, // Cloud Function does not store qualifier key
            sleepValidation: sleep?["validation"] as? String,
            // Stress Details (extracted from timelines)
            currentBodyBattery: currentBB,
            bodyBatteryAtWake: wakeBB,
            currentStressLevel: currentStress,
            // HRV
            lastNightAvg: hrv?["lastNightAvg"] as? Int,
            lastNight5MinHigh: hrv?["lastNight5MinHigh"] as? Int,
            // User Metrics
            vo2Max: metrics?["vo2Max"] as? Double,
            fitnessAge: metrics?["fitnessAge"] as? Int,
            // 7-day averages (computed)
            restingHR7DayAvg: avgRHR,
            hrvWeeklyAvg: avgHRV
        )
    }
```

### 4.5 Firestore Field → Internal Model Mapping

| Firestore Field | Firestore Type | Internal Field | Notes |
|---|---|---|---|
| `restingHeartRate` | Int | `restingHeartRateInBeatsPerMinute` | dailySummaries |
| `averageHeartRate` | Int | `averageHeartRateInBeatsPerMinute` | dailySummaries |
| `stressAverage` | Int | `averageStressLevel` | 1-100, -1 = insufficient |
| `stressMax` | Int | `maxStressLevel` | dailySummaries |
| `stressDurationSeconds` | Int | `stressDurationInSeconds` | dailySummaries |
| `restStressDurationSeconds` | Int | `restStressDurationInSeconds` | dailySummaries |
| `lowStressDurationSeconds` | Int | `lowStressDurationInSeconds` | dailySummaries |
| `mediumStressDurationSeconds` | Int | `mediumStressDurationInSeconds` | dailySummaries |
| `highStressDurationSeconds` | Int | `highStressDurationInSeconds` | dailySummaries |
| `stressQualifier` | String | `stressQualifier` | "calm", "balanced", etc. |
| `steps` | Int | `steps` | dailySummaries |
| `activeCalories` | Int | `activeKilocalories` | dailySummaries |
| `moderateIntensitySeconds` | Int | `moderateIntensityDurationInSeconds` | dailySummaries |
| `vigorousIntensitySeconds` | Int | `vigorousIntensityDurationInSeconds` | dailySummaries |
| `bodyBatteryCharged` | Int | `bodyBatteryChargedValue` | dailySummaries |
| `bodyBatteryDrained` | Int | `bodyBatteryDrainedValue` | dailySummaries |
| `totalMinutes` | Int | `sleepDurationInSeconds` | sleep, converted ×60 |
| `deepSleepMinutes` | Int | `deepSleepDurationInSeconds` | sleep, converted ×60 |
| `lightSleepMinutes` | Int | `lightSleepDurationInSeconds` | sleep, converted ×60 |
| `remSleepMinutes` | Int | `remSleepInSeconds` | sleep, converted ×60 |
| `awakeMinutes` | Int | `awakeDurationInSeconds` | sleep, converted ×60 |
| `garminSleepScore` | Int | `sleepScoreValue` | 0-100, sleep |
| `validation` | String | `sleepValidation` | sleep |
| `bodyBatteryTimeline` | Array | `currentBodyBattery` / `bodyBatteryAtWake` | stressDetails, extracted |
| `stressTimeline` | Array | `currentStressLevel` | stressDetails, extracted |
| `lastNightAvg` | Int | `lastNightAvg` | hrv, RMSSD ms |
| `lastNight5MinHigh` | Int | `lastNight5MinHigh` | hrv |
| `vo2Max` | Double | `vo2Max` | userMetrics |
| `fitnessAge` | Int | `fitnessAge` | userMetrics |

### 4.6 Timeline Extraction (Body Battery & Stress)

Body battery and current stress are extracted from array timelines in the stressDetails document:

```swift
    /// Extract current and wake body battery from stressDetails bodyBatteryTimeline.
    /// The Cloud Function stores an array of { offsetSeconds, value } objects.
    /// First entry ≈ wake BB, last entry ≈ current BB.
    private func extractBodyBattery(from stressDoc: [String: Any]?) -> (current: Int?, wake: Int?) {
        guard let doc = stressDoc,
              let timeline = doc["bodyBatteryTimeline"] as? [[String: Any]]
        else { return (nil, nil) }

        let sorted = timeline.compactMap { entry -> (Int, Int)? in
            guard let offset = entry["offsetSeconds"] as? Int,
                  let value = entry["value"] as? Int
            else { return nil }
            return (offset, value)
        }.sorted { $0.0 < $1.0 }

        let wake = sorted.first?.1
        let current = sorted.last?.1
        return (current, wake)
    }

    /// Extract the most recent stress level from stressDetails stressTimeline.
    /// The Cloud Function stores an array of { offsetSeconds, level } objects.
    /// Values: 1-100 are real stress. Negative values are special (-1=off_wrist, -2=motion, etc).
    private func extractCurrentStress(from stressDoc: [String: Any]?) -> Int? {
        guard let doc = stressDoc,
              let timeline = doc["stressTimeline"] as? [[String: Any]]
        else { return nil }

        let sorted = timeline.compactMap { entry -> (Int, Int)? in
            guard let offset = entry["offsetSeconds"] as? Int,
                  let level = entry["level"] as? Int
            else { return nil }
            return (offset, level)
        }.sorted { $0.0 > $1.0 } // newest first

        // Find the most recent valid stress reading (positive values only)
        return sorted.first(where: { $0.1 > 0 })?.1
    }
```

### 4.7 7-Day Average Computation

```swift
    private func compute7DayAvgRHR(from dailies: [[String: Any]]) -> Int? {
        let rhrValues = dailies.compactMap { $0["restingHeartRate"] as? Int }
        guard !rhrValues.isEmpty else { return nil }
        return rhrValues.reduce(0, +) / rhrValues.count
    }

    private func compute7DayAvgHRV(from hrvDocs: [[String: Any]]) -> Int? {
        let hrvValues = hrvDocs.compactMap { $0["lastNightAvg"] as? Int }
        guard !hrvValues.isEmpty else { return nil }
        return hrvValues.reduce(0, +) / hrvValues.count
    }
```

### 4.8 Firestore Document Access Helpers

```swift
    /// Get the collection reference for date-keyed documents.
    /// Path: /users/{uid}/garminData/{dataType}/dates  (5 segments — valid collection path)
    private func datesCollection(for dataType: String) -> CollectionReference? {
        guard let db = GarminFirebaseManager.firestore else { return nil }
        return db.collection(config.basePath)
                 .document(dataType)
                 .collection(config.dateSubcollection)
    }

    /// Fetch a single document by data type and calendar date.
    /// Path: /users/{uid}/garminData/{dataType}/dates/{calendarDate}  (6 segments — valid document path)
    private func fetchDocument(dataType: String, documentID: String) async -> [String: Any]? {
        guard let ref = datesCollection(for: dataType) else { return nil }

        do {
            let snapshot = try await ref.document(documentID).getDocument()
            return snapshot.data()
        } catch {
            debug(.service, "Garmin Firestore: fetch(\(dataType)/\(documentID)) failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetch the most recent document on or before a given date.
    /// Documents are keyed by calendarDate (yyyy-MM-dd), so lexicographic ordering works.
    private func fetchMostRecentDocument(dataType: String, onOrBefore dateString: String) async -> [String: Any]? {
        guard let ref = datesCollection(for: dataType) else { return nil }

        do {
            // First try the exact date (most common case)
            let exactDoc = try await ref.document(dateString).getDocument()
            if exactDoc.exists, let data = exactDoc.data() {
                return data
            }

            // Fall back to querying by document ID (lexicographic order on calendarDate keys)
            let snapshot = try await ref
                .whereField(FieldPath.documentID(), isLessThanOrEqualTo: dateString)
                .order(by: FieldPath.documentID(), descending: true)
                .limit(to: 1)
                .getDocuments()
            return snapshot.documents.first?.data()
        } catch {
            debug(.service, "Garmin Firestore: fetchMostRecent(\(dataType), ≤\(dateString)) failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetch documents for the last N days (for computing averages).
    private func fetchDocuments(dataType: String, lastDays: Int) async -> [[String: Any]] {
        guard let ref = datesCollection(for: dataType) else { return [] }

        let cutoff = calendarDateString(for: Date().addingTimeInterval(-Double(lastDays) * 86400))

        do {
            let snapshot = try await ref
                .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: cutoff)
                .order(by: FieldPath.documentID(), descending: true)
                .getDocuments()
            return snapshot.documents.map { $0.data() }
        } catch {
            debug(.service, "Garmin Firestore: fetchDocuments(\(dataType), \(lastDays)d) failed — \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Helpers

    private func calendarDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func minutesToSeconds(_ minutes: Int?) -> Int? {
        guard let m = minutes else { return nil }
        return m * 60
    }
}
```

---

## 5. Data Model: GarminContextSnapshot

**File: `Trio/Sources/Models/GarminContextSnapshot.swift`**

A point-in-time snapshot of all Garmin health data relevant to insulin sensitivity. All fields are optional (data may not be available for a given day).

```swift
import Foundation

struct GarminContextSnapshot: Codable {
    let queryTime: Date

    // === Daily Summary (from "dailies" collection) ===
    let restingHeartRateInBeatsPerMinute: Int?
    let averageHeartRateInBeatsPerMinute: Int?  // 7-day avg HR
    let averageStressLevel: Int?                // 1-100, or -1 if insufficient data
    let maxStressLevel: Int?
    let stressDurationInSeconds: Int?
    let restStressDurationInSeconds: Int?
    let lowStressDurationInSeconds: Int?
    let mediumStressDurationInSeconds: Int?
    let highStressDurationInSeconds: Int?
    let stressQualifier: String?                // "calm", "balanced", "stressful", "very_stressful"
    let steps: Int?
    let activeKilocalories: Int?
    let moderateIntensityDurationInSeconds: Int?
    let vigorousIntensityDurationInSeconds: Int?
    let bodyBatteryChargedValue: Int?           // BB charged during monitoring
    let bodyBatteryDrainedValue: Int?           // BB drained during monitoring

    // === Yesterday's Daily Summary (for delayed sensitivity effects) ===
    let yesterdaySteps: Int?
    let yesterdayActiveKilocalories: Int?
    let yesterdayModerateIntensityDurationInSeconds: Int?
    let yesterdayVigorousIntensityDurationInSeconds: Int?

    // === Sleep Summary ===
    let sleepDurationInSeconds: Int?
    let deepSleepDurationInSeconds: Int?
    let lightSleepDurationInSeconds: Int?
    let remSleepInSeconds: Int?
    let awakeDurationInSeconds: Int?
    let sleepScoreValue: Int?                   // 0-100
    let sleepScoreQualifier: String?            // EXCELLENT/GOOD/FAIR/POOR
    let sleepValidation: String?                // AUTO_FINAL, ENHANCED_FINAL, etc.

    // === Stress Details (extracted from timelines) ===
    let currentBodyBattery: Int?                // latest BB reading
    let bodyBatteryAtWake: Int?                 // earliest BB of the day (recovery proxy)
    let currentStressLevel: Int?                // latest stress (1-100, positive only)

    // === HRV Summary ===
    let lastNightAvg: Int?                      // lastNightAvg HRV (RMSSD ms)
    let lastNight5MinHigh: Int?                 // max 5-min HRV window

    // === User Metrics ===
    let vo2Max: Double?
    let fitnessAge: Int?

    // === 7-Day Averages (computed from historical documents) ===
    let restingHR7DayAvg: Int?
    let hrvWeeklyAvg: Int?

    // MARK: - Computed Deltas

    /// Resting HR delta from 7-day average (positive = elevated = more resistant)
    var restingHRDelta: Int? {
        guard let current = restingHeartRateInBeatsPerMinute, let avg = restingHR7DayAvg else { return nil }
        return current - avg
    }

    /// HRV delta as percentage from weekly average (negative = suppressed = more resistant)
    var hrvDeltaPercent: Double? {
        guard let current = lastNightAvg, let avg = hrvWeeklyAvg, avg > 0 else { return nil }
        return (Double(current - avg) / Double(avg)) * 100
    }

    /// Total sleep in minutes
    var totalSleepMinutes: Int? {
        guard let seconds = sleepDurationInSeconds else { return nil }
        return seconds / 60
    }

    /// Total intensity minutes today (moderate + vigorous)
    var intensityMinutesToday: Int? {
        let moderate = (moderateIntensityDurationInSeconds ?? 0) / 60
        let vigorous = (vigorousIntensityDurationInSeconds ?? 0) / 60
        let total = moderate + vigorous
        return total > 0 ? total : nil
    }

    /// Yesterday's total intensity minutes
    var yesterdayIntensityMinutes: Int? {
        let moderate = (yesterdayModerateIntensityDurationInSeconds ?? 0) / 60
        let vigorous = (yesterdayVigorousIntensityDurationInSeconds ?? 0) / 60
        let total = moderate + vigorous
        return total > 0 ? total : nil
    }
}
```

---

## 6. Sensitivity Model: GarminSensitivityModel

**File: `Trio/Sources/Models/GarminSensitivityModel.swift`**

Rule-based model that converts the ~40-field `GarminContextSnapshot` into a single `insulinDemandFactor` (0.70–1.30, symmetric ±30% range). The factor is computed by accumulating additive impacts from 10 health signals, then inverting and clamping.

```swift
import Foundation

struct GarminSensitivityModel {

    struct SensitivityResult {
        let sensitivityFactor: Double       // raw (internal, pre-clamp)
        let insulinDemandFactor: Double     // 0.70-1.30 (used in code, ±30% cap)
        let contributions: [Contribution]   // breakdown of what affected the result

        struct Contribution {
            let metric: String      // e.g., "Sleep Score"
            let value: String       // e.g., "42/100"
            let impact: Double      // e.g., -0.22 (negative = more resistant)
            let description: String // e.g., "Terrible sleep: 22% more resistant"
        }
    }

    static func computeDemandFactor(from ctx: GarminContextSnapshot?) -> SensitivityResult {
        guard let ctx = ctx else {
            return SensitivityResult(
                sensitivityFactor: 1.0,
                insulinDemandFactor: 1.0,
                contributions: [SensitivityResult.Contribution(
                    metric: "Garmin Data",
                    value: "Unavailable",
                    impact: 0,
                    description: "No Garmin data — using baseline"
                )]
            )
        }

        var factor = 1.0
        var contributions: [SensitivityResult.Contribution] = []
```

### 6.1 Signal Breakdown

The model evaluates these 10 signals additively:

| Signal | Source Field | Thresholds | Max Impact |
|---|---|---|---|
| **Sleep Score** | `sleepScoreValue` | <40: -0.11, <55: -0.08, <70: -0.04, >=85: +0.03 | -11% to +3% |
| **Sleep Duration** | `totalSleepMinutes` | <300min: -0.05, <360min: -0.03 | -5% |
| **Body Battery** | `currentBodyBattery` | <15: -0.09, <30: -0.06, <50: -0.03, >=75: +0.03 | -9% to +3% |
| **Current Stress** | `currentStressLevel` | >75: -0.04, >60: -0.02 | -4% |
| **Avg Stress Today** | `averageStressLevel` | >60: -0.03, >45: -0.02 | -3% |
| **Resting HR Delta** | `restingHRDelta` | >12bpm: -0.06, >8bpm: -0.04, <-5bpm: +0.02 | -6% to +2% |
| **HRV Delta** | `hrvDeltaPercent` | <-20%: -0.04, <-10%: -0.02, >15%: +0.02 | -4% to +2% |
| **Yesterday Activity** | `yesterdayActiveKilocalories` | >600cal: +0.08, >400cal: +0.05, >250cal: +0.03 | +8% |
| **Today Activity** | `activeKilocalories` | >400cal: +0.04, >200cal: +0.02 | +4% |
| **Vigorous Exercise** | `yesterdayVigorousIntensityDurationInSeconds` | >45min: +0.04, >20min: +0.02 | +4% |

### 6.2 Demand Factor Computation

```swift
        // --- Convert to insulin demand factor and clamp directly to ±30% ---
        // V3 Change: Clamp the demand factor symmetrically instead of the sensitivity
        // factor. This gives a clean ±30% range (0.70 to 1.30) without the asymmetry
        // that the 1/x inversion previously caused (old range was 0.71 to 1.67).
        let rawDemandFactor = 1.0 / factor
        let demandFactor = max(0.70, min(1.30, rawDemandFactor))

        return SensitivityResult(
            sensitivityFactor: factor,
            insulinDemandFactor: demandFactor,
            contributions: contributions
        )
    }
}
```

**Interpretation:**
- `factor` starts at 1.0, negative impacts (poor sleep, high stress) reduce it below 1.0
- `1.0 / factor` inverts: a sensitivity of 0.85 becomes a demand of ~1.18 (18% more insulin needed)
- Clamped to `[0.70, 1.30]` for safety

---

## 7. Integration Points: Where Demand Factor Is Used

The Garmin demand factor is fetched and applied at three locations:

### 7.1 Treatment Recommendation (TreatmentsStateModel, line ~437)

When the Cronometer recommendation panel loads, it fetches the Garmin snapshot and displays the demand factor:

```swift
// Fetch Garmin demand factor if V2 + Garmin enabled
let trioSettings = settingsManager.settings
if trioSettings.useV2MacroAbsorption, trioSettings.garminEnabled, GarminFirebaseManager.isSignedIn {
    let service = GarminFirestoreService()
    let snapshot = await service.fetchContext()
    let sensitivityResult = GarminSensitivityModel.computeDemandFactor(from: snapshot)
    v2DemandFactor = sensitivityResult.insulinDemandFactor
    v2DemandContributions = sensitivityResult.contributions
} else {
    v2DemandFactor = 1.0
    v2DemandContributions = []
}
```

### 7.2 Outcome Recording (TreatmentsStateModel, line ~1068)

When a dose is confirmed, the Garmin snapshot is attached to the outcome record for later export/analysis:

```swift
// Attach Garmin snapshot (cached from recommendation fetch)
let trioSettings = await MainActor.run { settingsManager.settings }
if trioSettings.garminEnabled, GarminFirebaseManager.isSignedIn {
    let service = GarminFirestoreService()
    let snapshot = await service.fetchContext()
    pendingOutcome = pendingOutcome.withGarminSnapshot(snapshot)
}
```

### 7.3 CarbsStorage Engine (CarbsStorage.swift, line ~253)

When the macro absorption engine processes selected meals into carb entries, the demand factor scales the output:

```swift
// Fetch Garmin sensitivity factor if enabled
var demandFactor = 1.0
if trioSettings.garminEnabled, GarminFirebaseManager.isSignedIn {
    let service = GarminFirestoreService()
    let snapshot = await service.fetchContext()
    let sensitivityResult = GarminSensitivityModel.computeDemandFactor(from: snapshot)
    demandFactor = sensitivityResult.insulinDemandFactor
    debug(.service, "Garmin demand factor: \(demandFactor) (\(sensitivityResult.contributions.count) contributions)")
}
```

### 7.4 Guard Pattern

All three sites follow the same pattern:
1. Check `trioSettings.garminEnabled` (user toggle)
2. Check `GarminFirebaseManager.isSignedIn` (Firebase auth succeeded)
3. Create `GarminFirestoreService()` (uses 5-min cache)
4. Call `fetchContext()` → `GarminContextSnapshot?`
5. Call `GarminSensitivityModel.computeDemandFactor(from:)` → `SensitivityResult`
6. Use `.insulinDemandFactor` (0.70–1.30)

---

## 8. ConnectIQ Watch Communication

**File: `Trio/Sources/Services/WatchManager/GarminManager.swift`** (651 lines)

The watch communication system is independent of the Firestore health data. It sends loop data (glucose, IOB, COB, trend, etc.) to a Garmin watchface and data field via the ConnectIQ SDK.

### 8.1 Protocol

```swift
protocol GarminManager {
    func selectDevices() -> AnyPublisher<[IQDevice], Never>
    func updateDeviceList(_ devices: [IQDevice])
    func sendWatchStateData(_ data: Data)
    var devices: [IQDevice] { get }
}
```

### 8.2 Initialization & Data Sources

```swift
final class BaseGarminManager: NSObject, GarminManager, Injectable {
    @Injected() private var notificationCenter: NotificationCenter!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var determinationStorage: DeterminationStorage!
    @Injected() private var iobService: IOBService!

    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [GarminDevice] = []

    private let router: Router
    private let connectIQ = ConnectIQ.sharedInstance()
    private var watchApps: [IQApp] = []
    private let watchStateSubject = PassthroughSubject<NSDictionary, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?
    private(set) var devices: [IQDevice] = [] {
        didSet {
            persistedDevices = devices.map(GarminDevice.init)
            registerDevices(devices)
        }
    }
    private var units: GlucoseUnits = .mgdL
```

### 8.3 Watch App UUIDs

```swift
private enum Config {
    /// Watchface UUID
    static let watchfaceUUID = UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")

    /// Data field UUID
    static let watchdataUUID = UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
}
```

### 8.4 Data Update Triggers

Watch state is rebuilt and sent when any of these change:
1. **Glucose updates** — `glucoseStorage.updatePublisher`
2. **IOB changes** — `iobService.iobPublisher`
3. **OrefDetermination changes** — CoreData `NSManagedObjectContextDidSave` filtered by entity name
4. **GlucoseStored deletions** — CoreData change notifications
5. **Settings changes** — `SettingsObserver` callback (e.g., unit change mg/dL ↔ mmol/L)
6. **Watch requests** — Watch sends `"status"` message, triggers response

### 8.5 Throttling

All updates are throttled to **10-second intervals** via Combine:

```swift
private func subscribeToWatchState() {
    watchStateSubject
        .throttle(for: .seconds(10), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] state in
            self?.broadcastStateToWatchApps(state)
        }
        .store(in: &cancellables)
}
```

### 8.6 Building Watch State

```swift
func setupGarminWatchState() async throws -> GarminWatchState {
    guard !devices.isEmpty else {
        return GarminWatchState()
    }

    let glucoseIds = try await fetchGlucose()
    let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
        predicate: NSPredicate.predicateFor30MinAgoForDetermination
    )

    let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
        .getNSManagedObject(with: glucoseIds, context: backgroundContext)
    let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
        .getNSManagedObject(with: determinationIds, context: backgroundContext)

    return await backgroundContext.perform {
        var watchState = GarminWatchState()

        let iobValue = self.iobService.currentIOB ?? 0
        watchState.iob = self.iobFormatterWithOneFractionDigit(iobValue)

        if let latestDetermination = determinationObjects.first {
            watchState.lastLoopDateInterval = latestDetermination.timestamp.map {
                guard $0.timeIntervalSince1970 > 0 else { return 0 }
                return UInt64($0.timeIntervalSince1970)
            }

            let cobNumber = NSNumber(value: latestDetermination.cob)
            watchState.cob = Formatter.integerFormatter.string(from: cobNumber)

            let insulinSensitivity = latestDetermination.insulinSensitivity ?? 0
            let eventualBG = latestDetermination.eventualBG ?? 0

            if self.units == .mgdL {
                watchState.isf = insulinSensitivity.description
                watchState.eventualBGRaw = eventualBG.description
            } else {
                let parsedIsf = Double(truncating: insulinSensitivity).asMmolL
                let parsedEventualBG = Double(truncating: eventualBG).asMmolL
                watchState.isf = parsedIsf.description
                watchState.eventualBGRaw = parsedEventualBG.description
            }
        }

        guard let latestGlucose = glucoseObjects.first else {
            return watchState
        }

        if self.units == .mgdL {
            watchState.glucose = "\(latestGlucose.glucose)"
        } else {
            let mgdlValue = Decimal(latestGlucose.glucose)
            let latestGlucoseValue = Double(truncating: mgdlValue.asMmolL as NSNumber)
            watchState.glucose = "\(latestGlucoseValue)"
        }

        watchState.trendRaw = latestGlucose.direction ?? "--"

        if glucoseObjects.count >= 2 {
            var deltaValue = Decimal(glucoseObjects[0].glucose - glucoseObjects[1].glucose)
            if self.units == .mmolL {
                deltaValue = Double(truncating: deltaValue as NSNumber).asMmolL
            }
            let formattedDelta = deltaValue.description
            watchState.delta = deltaValue < 0 ? "\(formattedDelta)" : "+\(formattedDelta)"
        }

        return watchState
    }
}
```

### 8.7 Device Registration & Message Passing

```swift
private func registerDevices(_ devices: [IQDevice]) {
    watchApps.removeAll()

    for device in devices {
        connectIQ?.register(forDeviceEvents: device, delegate: self)

        guard
            let watchfaceUUID = Config.watchfaceUUID,
            let watchfaceApp = IQApp(uuid: watchfaceUUID, store: UUID(), device: device)
        else { continue }

        guard
            let watchdataUUID = Config.watchdataUUID,
            let watchDataFieldApp = IQApp(uuid: watchdataUUID, store: UUID(), device: device)
        else { continue }

        watchApps.append(watchfaceApp)
        watchApps.append(watchDataFieldApp)

        connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
    }
}

private func broadcastStateToWatchApps(_ state: NSDictionary) {
    watchApps.forEach { app in
        connectIQ?.getAppStatus(app) { [weak self] status in
            guard status?.isInstalled == true else { return }
            self?.sendMessage(state, to: app)
        }
    }
}

private func sendMessage(_ msg: NSDictionary, to app: IQApp) {
    connectIQ?.sendMessage(
        msg,
        to: app,
        progress: { _, _ in },
        completion: { result in
            switch result {
            case .success:
                debug(.watchManager, "Garmin: Successfully sent message to \(app.uuid!)")
            default:
                debug(.watchManager, "Garmin: Unknown result or failed to send message to \(app.uuid!)")
            }
        }
    )
}
```

### 8.8 Device Selection & URL Handling

Garmin Connect returns device selections via a URL scheme. The app registers `"Trio"` as the URL scheme:

```swift
init(resolver: Resolver) {
    // ...
    connectIQ?.initialize(withUrlScheme: "Trio", uiOverrideDelegate: self)
    restoreDevices()
    subscribeToOpenFromGarminConnect()
    // ...
}

private func subscribeToOpenFromGarminConnect() {
    notificationCenter
        .publisher(for: .openFromGarminConnect)
        .sink { [weak self] notification in
            guard let self = self,
                  let url = notification.object as? URL
            else { return }
            self.parseDevices(for: url)
        }
        .store(in: &cancellables)
}

private func parseDevices(for url: URL) {
    let parsed = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice]
    devices = parsed ?? []
    deviceSelectionPromise?(.success(devices))
    deviceSelectionPromise = nil
}

func selectDevices() -> AnyPublisher<[IQDevice], Never> {
    Future { [weak self] promise in
        guard let self = self else {
            promise(.success([]))
            return
        }
        self.deviceSelectionPromise = promise
        self.connectIQ?.showDeviceSelection()
    }
    .timeout(.seconds(120), scheduler: DispatchQueue.main)
    .replaceEmpty(with: [])
    .eraseToAnyPublisher()
}
```

### 8.9 ConnectIQ Delegate Methods

```swift
extension BaseGarminManager: IQUIOverrideDelegate, IQDeviceEventDelegate, IQAppMessageDelegate {
    func needsToInstallConnectMobile() {
        let messageCont = MessageContent(
            content: "The app Garmin Connect must be installed to use Trio.\nGo to the App Store to download it.",
            type: .warning,
            subtype: .misc,
            title: "Garmin is not available"
        )
        router.alertMessage.send(messageCont)
    }

    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        switch status {
        case .invalidDevice: debug(.watchManager, "Garmin: invalidDevice")
        case .bluetoothNotReady: debug(.watchManager, "Garmin: bluetoothNotReady")
        case .notFound: debug(.watchManager, "Garmin: notFound")
        case .notConnected: debug(.watchManager, "Garmin: notConnected")
        case .connected: debug(.watchManager, "Garmin: connected")
        @unknown default: debug(.watchManager, "Garmin: unknown state")
        }
    }

    func receivedMessage(_ message: Any, from app: IQApp) {
        Task {
            guard let statusString = message as? String, statusString == "status" else { return }
            do {
                let watchState = try await self.setupGarminWatchState()
                let watchStateData = try JSONEncoder().encode(watchState)
                sendWatchStateData(watchStateData)
            } catch {
                debug(.watchManager, "Garmin: Cannot encode watch state: \(error)")
            }
        }
    }
}
```

---

## 9. Data Model: GarminWatchState

**File: `Trio/Sources/Models/GarminWatchState.swift`**

The data sent to the watch on each update:

```swift
import Foundation
import SwiftUI

struct GarminWatchState: Hashable, Equatable, Sendable, Encodable {
    var glucose: String?
    var trendRaw: String?
    var delta: String?
    var iob: String?
    var cob: String?
    var lastLoopDateInterval: UInt64?
    var eventualBGRaw: String?
    var isf: String?

    static func == (lhs: GarminWatchState, rhs: GarminWatchState) -> Bool {
        lhs.glucose == rhs.glucose &&
            lhs.trendRaw == rhs.trendRaw &&
            lhs.delta == rhs.delta &&
            lhs.iob == rhs.iob &&
            lhs.cob == rhs.cob &&
            lhs.lastLoopDateInterval == rhs.lastLoopDateInterval &&
            lhs.eventualBGRaw == rhs.eventualBGRaw &&
            lhs.isf == rhs.isf
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(glucose)
        hasher.combine(trendRaw)
        hasher.combine(delta)
        hasher.combine(iob)
        hasher.combine(cob)
        hasher.combine(lastLoopDateInterval)
        hasher.combine(eventualBGRaw)
        hasher.combine(isf)
    }
}
```

**Field descriptions:**

| Field | Type | Source | Example |
|---|---|---|---|
| `glucose` | String? | Latest `GlucoseStored.glucose` | `"142"` or `"7.9"` |
| `trendRaw` | String? | `GlucoseStored.direction` | `"Flat"`, `"FortyFiveUp"` |
| `delta` | String? | Diff of last two glucose readings | `"+3"`, `"-8"` |
| `iob` | String? | `iobService.currentIOB` formatted | `"2.3"` |
| `cob` | String? | `OrefDetermination.cob` | `"45"` |
| `lastLoopDateInterval` | UInt64? | `OrefDetermination.timestamp` as epoch | `1705344000` |
| `eventualBGRaw` | String? | `OrefDetermination.eventualBG` | `"120"` |
| `isf` | String? | `OrefDetermination.insulinSensitivity` | `"40"` |

---

## 10. Data Model: GarminDevice

**File: `Trio/Sources/Models/GarminDevice.swift`**

Codable wrapper around `IQDevice` for persistence:

```swift
import ConnectIQ

struct GarminDevice: Codable, Equatable {
    let id: UUID
    let modelName: String
    let friendlyName: String

    init(iqDevice: IQDevice) {
        id = iqDevice.uuid
        modelName = iqDevice.modelName
        friendlyName = iqDevice.modelName
    }

    var iqDevice: IQDevice {
        IQDevice(id: id, modelName: modelName, friendlyName: friendlyName)
    }
}
```

Persisted via `@Persisted(key: "BaseGarminManager.persistedDevices")` in `BaseGarminManager`.

---

## 11. Settings & UI

### 11.1 Setting: `garminEnabled`

**File: `Trio/Sources/Models/TrioSettings.swift`** (line 94)

```swift
var garminEnabled: Bool = false
```

Published in `SettingsStateModel` (line 27):
```swift
@Published var garminEnabled = false
```

### 11.2 V2GarminSettingsView

**File: `Trio/Sources/Modules/Settings/View/Subviews/V2GarminSettingsView.swift`**

```swift
import SwiftUI

struct V2GarminSettingsView: View {
    @ObservedObject var state: Settings.StateModel

    var body: some View {
        List {
            Section(header: Text("Garmin Sensitivity Integration")) {
                Toggle("Enable Garmin Sensitivity", isOn: $state.garminEnabled)

                if state.garminEnabled {
                    HStack {
                        Text("Firebase Status")
                        Spacer()
                        Text("See Garmin Health Data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink(value: Screen.garminFirestoreStatus) {
                        Text("Garmin Health Data")
                    }
                }
            }

            if state.garminEnabled {
                Section(header: Text("How It Works")) {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow(icon: "moon.zzz.fill", color: .indigo,
                                title: "Sleep Quality",
                                desc: "Poor sleep reduces insulin sensitivity (up to 1.67x demand)")

                        infoRow(icon: "figure.run", color: .green,
                                title: "Activity Level",
                                desc: "Recent exercise improves sensitivity (down to 0.60x demand)")

                        infoRow(icon: "heart.fill", color: .red,
                                title: "Resting Heart Rate",
                                desc: "Elevated RHR suggests stress or illness (increased demand)")

                        infoRow(icon: "waveform.path.ecg", color: .orange,
                                title: "HRV",
                                desc: "Low HRV indicates reduced recovery (increased demand)")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func infoRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
```

### 11.3 GarminFirestoreStatusView

**File: `Trio/Sources/Modules/Settings/View/Subviews/GarminFirestoreStatusView.swift`**

Connection test UI with 3-step verification:

```swift
import SwiftUI

struct GarminFirestoreStatusView: View {
    @State private var configStatus: CheckStatus = .unknown
    @State private var authStatus: CheckStatus = .unknown
    @State private var dataStatus: CheckStatus = .unknown
    @State private var isTesting = false
    @State private var latestSnapshot: GarminContextSnapshot?
    @State private var errorMessage: String?

    enum CheckStatus {
        case unknown, checking, pass, fail

        var icon: String {
            switch self {
            case .unknown: return "circle.dashed"
            case .checking: return "arrow.trianglehead.2.clockwise"
            case .pass: return "checkmark.circle.fill"
            case .fail: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .checking: return .orange
            case .pass: return .green
            case .fail: return .red
            }
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Connection Status")) {
                statusRow(label: "Configuration", status: configStatus, detail: configDetail)
                statusRow(label: "Firebase Sign-In", status: authStatus, detail: authDetail)
                statusRow(label: "Firestore Data", status: dataStatus, detail: dataDetail)
            }

            Section {
                Button {
                    Task { await runConnectionTest() }
                } label: {
                    HStack {
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Testing...")
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Test Connection")
                        }
                        Spacer()
                    }
                }
                .disabled(isTesting)
            }

            if let error = errorMessage {
                Section(header: Text("Error Details")) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = latestSnapshot {
                Section(header: Text("Latest Garmin Data")) {
                    dataRow("Sleep Score", value: snapshot.sleepScoreValue.map { "\($0)/100" })
                    dataRow("Sleep Duration", value: snapshot.totalSleepMinutes.map { "\($0 / 60)h \($0 % 60)m" })
                    dataRow("Resting HR", value: snapshot.restingHeartRateInBeatsPerMinute.map { "\($0) bpm" })
                    dataRow("HRV (last night)", value: snapshot.lastNightAvg.map { "\($0) ms" })
                    dataRow("Body Battery", value: snapshot.currentBodyBattery.map { "\($0)/100" })
                    dataRow("Stress Level", value: snapshot.currentStressLevel.map { "\($0)/100" })
                    dataRow("Active Calories", value: snapshot.activeKilocalories.map { "\($0) kcal" })
                    dataRow("Steps", value: snapshot.steps.map { "\($0)" })
                }
            }

            Section(header: Text("Configuration")) {
                configInfoRow("Project ID", value: maskedValue(GarminFirebaseConstants.projectID))
                configInfoRow("User ID", value: maskedValue(GarminFirebaseConstants.firestoreUserID))
                configInfoRow("Auth Email", value: maskedValue(GarminFirebaseConstants.authEmail))
            }
        }
        .navigationTitle("Garmin Health Data")
        .navigationBarTitleDisplayMode(.automatic)
        .onAppear {
            checkInitialStatus()
        }
    }

    // ... (statusRow, dataRow, configInfoRow helper views)

    private func checkInitialStatus() {
        configStatus = GarminFirebaseConstants.isConfigured ? .pass : .fail
        authStatus = GarminFirebaseManager.isSignedIn ? .pass : .unknown
    }

    private func runConnectionTest() async {
        isTesting = true
        errorMessage = nil
        latestSnapshot = nil

        // Step 1: Check config
        configStatus = .checking
        try? await Task.sleep(nanoseconds: 200_000_000)

        guard GarminFirebaseConstants.isConfigured else {
            configStatus = .fail
            authStatus = .fail
            dataStatus = .fail
            errorMessage = "Firebase secrets were not injected at build time."
            isTesting = false
            return
        }
        configStatus = .pass

        // Step 2: Check auth (attempt sign-in if needed)
        authStatus = .checking
        await GarminFirebaseManager.configureAndSignIn()

        guard GarminFirebaseManager.isSignedIn else {
            authStatus = .fail
            dataStatus = .fail
            errorMessage = "Firebase sign-in failed."
            isTesting = false
            return
        }
        authStatus = .pass

        // Step 3: Try fetching data
        dataStatus = .checking
        let service = GarminFirestoreService()
        let snapshot = await service.fetchContext()

        if let snapshot {
            dataStatus = .pass
            latestSnapshot = snapshot
        } else {
            dataStatus = .fail
            errorMessage = "Signed in but no data found in Firestore."
        }

        isTesting = false
    }

    private func maskedValue(_ value: String) -> String {
        if value.hasPrefix("__") { return "Not configured" }
        if value.count <= 8 { return value }
        return String(value.prefix(4)) + "..." + String(value.suffix(4))
    }
}
```

### 11.4 Navigation Route

**File: `Trio/Sources/Router/Screen.swift`** (line 56)

```swift
case garminFirestoreStatus
```

---

## 12. File Inventory

### Files to Keep (Garmin Integration)

| File | Subsystem | Purpose |
|---|---|---|
| `Trio/Sources/Services/Garmin/GarminFirebaseConfig.swift` | Firestore | Build-time secret placeholders |
| `Trio/Sources/Services/Garmin/GarminFirestoreService.swift` | Firestore | Firebase auth + Firestore queries |
| `Trio/Sources/Models/GarminContextSnapshot.swift` | Firestore | ~40-field health data snapshot |
| `Trio/Sources/Models/GarminSensitivityModel.swift` | Firestore | Rule-based demand factor (0.70–1.30) |
| `Trio/Sources/Models/GarminDevice.swift` | Watch | Codable IQDevice wrapper |
| `Trio/Sources/Models/GarminWatchState.swift` | Watch | Data sent to watch face |
| `Trio/Sources/Services/WatchManager/GarminManager.swift` | Watch | ConnectIQ device management + state updates |
| `Trio/Sources/Modules/Settings/View/Subviews/V2GarminSettingsView.swift` | UI | Settings toggle + info |
| `Trio/Sources/Modules/Settings/View/Subviews/GarminFirestoreStatusView.swift` | UI | Connection test + data display |

### Integration Points in Other Files

| File | What to add/modify |
|---|---|
| `Trio/Sources/Models/TrioSettings.swift` | `garminEnabled: Bool` setting |
| `Trio/Sources/Modules/Settings/SettingsStateModel.swift` | `@Published var garminEnabled` + subscription |
| `Trio/Sources/Router/Screen.swift` | `.garminFirestoreStatus` case |
| Treatment/carb entry sites | Guard pattern: check enabled → fetch → compute → apply |

---

## 13. External Dependencies

| Dependency | Used By | Purpose |
|---|---|---|
| `FirebaseCore` | GarminFirestoreService | Secondary Firebase app configuration |
| `FirebaseAuth` | GarminFirestoreService | Email/password sign-in |
| `FirebaseFirestore` | GarminFirestoreService | Document queries |
| `ConnectIQ` (Garmin SDK) | GarminManager | Watch device management and messaging |

All Firebase dependencies are already present in Trio for Crashlytics. The ConnectIQ SDK is included as a framework for the existing Garmin watch support.

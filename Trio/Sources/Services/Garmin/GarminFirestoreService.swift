import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

// MARK: - Firebase App Manager

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

// MARK: - Firestore Configuration

struct GarminFirestoreConfig: Codable {
    var isEnabled: Bool = false
    var userID: String = ""

    /// Base path: /users/{userID}/garminData
    var basePath: String { "users/\(userID)/garminData" }

    var dailySummariesType: String = "dailySummaries"
    var sleepType: String = "sleep"
    var stressDetailsType: String = "stressDetails"
    var hrvType: String = "hrv"
    var userMetricsType: String = "userMetrics"
    var dateSubcollection: String = "dates"

    /// Cache duration — don't re-query within this interval (seconds)
    var cacheDurationSeconds: TimeInterval = 5 * 60
}

// MARK: - Firestore Service Protocol

protocol GarminFirestoreServiceProtocol {
    func fetchContext() async -> GarminContextSnapshot?
    var isConfigured: Bool { get }
}

// MARK: - Firestore Service Implementation

final class GarminFirestoreService: GarminFirestoreServiceProtocol {
    private var cachedSnapshot: GarminContextSnapshot?
    private var cacheTimestamp: Date?
    private let config: GarminFirestoreConfig

    var isConfigured: Bool {
        config.isEnabled && !config.userID.isEmpty && GarminFirebaseManager.isSignedIn
    }

    init(config: GarminFirestoreConfig) {
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

        let snapshot = await buildSnapshot()
        if snapshot != nil {
            cachedSnapshot = snapshot
            cacheTimestamp = Date()
        }
        return snapshot
    }

    // MARK: - Snapshot Builder

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
            yesterdaySteps: yDaily?["steps"] as? Int,
            yesterdayActiveKilocalories: yDaily?["activeCalories"] as? Int,
            yesterdayModerateIntensityDurationInSeconds: yDaily?["moderateIntensitySeconds"] as? Int,
            yesterdayVigorousIntensityDurationInSeconds: yDaily?["vigorousIntensitySeconds"] as? Int,
            sleepDurationInSeconds: minutesToSeconds(sleep?["totalMinutes"] as? Int),
            deepSleepDurationInSeconds: minutesToSeconds(sleep?["deepSleepMinutes"] as? Int),
            lightSleepDurationInSeconds: minutesToSeconds(sleep?["lightSleepMinutes"] as? Int),
            remSleepInSeconds: minutesToSeconds(sleep?["remSleepMinutes"] as? Int),
            awakeDurationInSeconds: minutesToSeconds(sleep?["awakeMinutes"] as? Int),
            sleepScoreValue: sleep?["garminSleepScore"] as? Int,
            sleepScoreQualifier: nil,
            sleepValidation: sleep?["validation"] as? String,
            currentBodyBattery: currentBB,
            bodyBatteryAtWake: wakeBB,
            currentStressLevel: currentStress,
            lastNightAvg: hrv?["lastNightAvg"] as? Int,
            lastNight5MinHigh: hrv?["lastNight5MinHigh"] as? Int,
            vo2Max: metrics?["vo2Max"] as? Double,
            fitnessAge: metrics?["fitnessAge"] as? Int,
            restingHR7DayAvg: avgRHR,
            hrvWeeklyAvg: avgHRV
        )
    }

    // MARK: - Timeline Extraction

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

    // MARK: - 7-Day Averages

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

    // MARK: - Firestore Access Helpers

    private func datesCollection(for dataType: String) -> CollectionReference? {
        guard let db = GarminFirebaseManager.firestore else { return nil }
        return db.collection(config.basePath)
            .document(dataType)
            .collection(config.dateSubcollection)
    }

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

    private func fetchMostRecentDocument(dataType: String, onOrBefore dateString: String) async -> [String: Any]? {
        guard let ref = datesCollection(for: dataType) else { return nil }

        do {
            let exactDoc = try await ref.document(dateString).getDocument()
            if exactDoc.exists, let data = exactDoc.data() {
                return data
            }

            let snapshot = try await ref
                .whereField(FieldPath.documentID(), isLessThanOrEqualTo: dateString)
                .order(by: FieldPath.documentID(), descending: true)
                .limit(to: 1)
                .getDocuments()
            return snapshot.documents.first?.data()
        } catch {
            debug(
                .service,
                "Garmin Firestore: fetchMostRecent(\(dataType), <=\(dateString)) failed — \(error.localizedDescription)"
            )
            return nil
        }
    }

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
            debug(
                .service,
                "Garmin Firestore: fetchDocuments(\(dataType), \(lastDays)d) failed — \(error.localizedDescription)"
            )
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

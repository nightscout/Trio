import Foundation

// MARK: - Nutrition Snapshot

/// A point-in-time record of cumulative daily macro totals from HealthKit.
/// Snapshots are recorded each time the HealthKit observer fires, and meals
/// are inferred by computing deltas between consecutive snapshots.
struct NutritionSnapshot: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let cumulativeCarbs: Double
    let cumulativeFat: Double
    let cumulativeProtein: Double
    let cumulativeFiber: Double
    /// Calendar day string, e.g. "2026-02-13"
    let forDate: String
    /// The most recent HealthKit sample creation date at the time of this snapshot.
    /// Cronometer writes all samples with midnight startDate, but the private
    /// creationDate reflects when the data was actually synced to HealthKit —
    /// i.e. when the user logged the food. Falls back to snapshot timestamp.
    let latestSampleCreationDate: Date?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cumulativeCarbs: Double,
        cumulativeFat: Double,
        cumulativeProtein: Double,
        cumulativeFiber: Double = 0,
        forDate: String,
        latestSampleCreationDate: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cumulativeCarbs = cumulativeCarbs
        self.cumulativeFat = cumulativeFat
        self.cumulativeProtein = cumulativeProtein
        self.cumulativeFiber = cumulativeFiber
        self.forDate = forDate
        self.latestSampleCreationDate = latestSampleCreationDate
    }
}

// MARK: - Inferred Meal Event

/// A meal event inferred from the delta between two consecutive snapshots.
struct InferredMealEvent: Identifiable {
    let id: UUID
    let detectedAt: Date
    let carbsDelta: Double
    let fatDelta: Double
    let proteinDelta: Double
    let fiberDelta: Double

    init(
        id: UUID = UUID(),
        detectedAt: Date,
        carbsDelta: Double,
        fatDelta: Double,
        proteinDelta: Double,
        fiberDelta: Double = 0
    ) {
        self.id = id
        self.detectedAt = detectedAt
        self.carbsDelta = carbsDelta
        self.fatDelta = fatDelta
        self.proteinDelta = proteinDelta
        self.fiberDelta = fiberDelta
    }

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
        }
        let hours = mins / 60
        let remaining = mins % 60
        if remaining == 0 {
            return "\(hours)h ago"
        }
        return "\(hours)h \(remaining)m ago"
    }
}

// MARK: - Snapshot Store

/// Persists nutrition snapshots and infers meal events from deltas.
/// Singleton so snapshots survive across view lifecycles.
final class NutritionSnapshotStore {
    static let shared = NutritionSnapshotStore()

    private var snapshots: [NutritionSnapshot] = []
    private let fileURL: URL
    private let retentionDays: Int = 14
    private let deduplicationWindow: TimeInterval = 2.0
    private static let mealGroupingWindow: TimeInterval = 15 * 60

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("nutrition_snapshots.json")
        loadFromDisk()
    }

    // MARK: - Public API

    /// Record a new snapshot. Deduplicates by 2-second window and identical values.
    func record(_ snapshot: NutritionSnapshot) {
        // Deduplicate: if a snapshot exists within 2 seconds with same cumulative values, skip
        let dominated = snapshots.contains { existing in
            abs(existing.timestamp.timeIntervalSince(snapshot.timestamp)) < deduplicationWindow &&
                existing.cumulativeCarbs == snapshot.cumulativeCarbs &&
                existing.cumulativeFat == snapshot.cumulativeFat &&
                existing.cumulativeProtein == snapshot.cumulativeProtein &&
                existing.cumulativeFiber == snapshot.cumulativeFiber &&
                existing.forDate == snapshot.forDate
        }
        guard !dominated else { return }

        // Also merge: replace any snapshot within 2s for the same day (updated totals)
        snapshots.removeAll { existing in
            abs(existing.timestamp.timeIntervalSince(snapshot.timestamp)) < deduplicationWindow &&
                existing.forDate == snapshot.forDate
        }

        snapshots.append(snapshot)
        saveToDisk()
    }

    /// Infer meal events from snapshot deltas over the last 8 hours.
    /// Groups events within 15 minutes into a single meal.
    /// Dose timestamps create group boundaries.
    func inferredMeals(
        mergeWindow: TimeInterval = 15 * 60,
        dosedTimestamps: Set<TimeInterval> = []
    ) -> [InferredMealEvent] {
        // Use the multi-day method to handle midnight spanning
        return inferredMealEvents(forLastHours: 8, mergeWindow: mergeWindow, dosedTimestamps: dosedTimestamps)
    }

    /// Infer meal events for the last N hours, spanning midnight if needed.
    func inferredMealEvents(
        forLastHours hours: Int,
        mergeWindow: TimeInterval = 15 * 60,
        dosedTimestamps: Set<TimeInterval> = []
    ) -> [InferredMealEvent] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        let calendar = Calendar.current
        let today = Self.dateFormatter.string(from: Date())

        // Always get today's events
        var allEvents = inferredMealEventsForDay(today, mergeWindow: mergeWindow, dosedTimestamps: dosedTimestamps)

        // If the window extends into yesterday, include yesterday's events too
        let startOfToday = calendar.startOfDay(for: Date())
        if cutoff < startOfToday,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())
        {
            let yesterdayStr = Self.dateFormatter.string(from: yesterday)
            allEvents += inferredMealEventsForDay(yesterdayStr, mergeWindow: mergeWindow, dosedTimestamps: dosedTimestamps)
        }

        return allEvents
            .filter { $0.detectedAt >= cutoff }
            .sorted { $0.detectedAt < $1.detectedAt }
    }

    /// Compute the meal delta between current HealthKit totals and the pre-meal baseline.
    /// Used for on-demand meal fetch: queries the store for the latest meal cluster
    /// and diffs against the snapshot before that cluster.
    func recordAndComputeLatestMeal(
        currentCarbs: Double,
        currentFat: Double,
        currentProtein: Double,
        currentFiber: Double = 0,
        latestSampleCreationDate: Date? = nil
    ) -> InferredMealEvent? {
        let today = Self.todayString()

        // Save a fresh snapshot with the current HealthKit totals
        let freshSnapshot = NutritionSnapshot(
            cumulativeCarbs: currentCarbs,
            cumulativeFat: currentFat,
            cumulativeProtein: currentProtein,
            cumulativeFiber: currentFiber,
            forDate: today,
            latestSampleCreationDate: latestSampleCreationDate
        )
        record(freshSnapshot)

        // Get all today's snapshots sorted ascending by time
        let allSnapshots = snapshots
            .filter { $0.forDate == today }
            .sorted { $0.timestamp < $1.timestamp }

        guard !allSnapshots.isEmpty else { return nil }

        // Walk backwards from the end, grouping snapshots within 15 minutes of each other.
        // The "meal cluster" is all consecutive snapshots where each pair is within 15 min.
        // The baseline is the snapshot just BEFORE this cluster.
        var mealStartIndex = allSnapshots.count - 1
        while mealStartIndex > 0 {
            let gap = allSnapshots[mealStartIndex].timestamp.timeIntervalSince(
                allSnapshots[mealStartIndex - 1].timestamp
            )
            if gap <= Self.mealGroupingWindow {
                mealStartIndex -= 1
            } else {
                break
            }
        }

        // The baseline is the snapshot just before the meal cluster
        let prev: NutritionSnapshot
        if mealStartIndex > 0 {
            prev = allSnapshots[mealStartIndex - 1]
        } else {
            // All snapshots are in one cluster — use midnight baseline (zero)
            prev = NutritionSnapshot(
                cumulativeCarbs: 0,
                cumulativeFat: 0,
                cumulativeProtein: 0,
                cumulativeFiber: 0,
                forDate: today
            )
        }

        let carbDelta = currentCarbs - prev.cumulativeCarbs
        let fatDelta = currentFat - prev.cumulativeFat
        let proteinDelta = currentProtein - prev.cumulativeProtein
        let fiberDelta = currentFiber - prev.cumulativeFiber

        // Only return a meal if there's a meaningful change
        guard carbDelta > 1 || fatDelta > 1 || proteinDelta > 1 else { return nil }

        return InferredMealEvent(
            detectedAt: allSnapshots[mealStartIndex].latestSampleCreationDate ?? allSnapshots[mealStartIndex].timestamp,
            carbsDelta: max(0, carbDelta),
            fatDelta: max(0, fatDelta),
            proteinDelta: max(0, proteinDelta),
            fiberDelta: max(0, fiberDelta)
        )
    }

    /// Current day string.
    static func todayString() -> String {
        dateFormatter.string(from: Date())
    }

    // MARK: - Per-Day Inference

    private func inferredMealEventsForDay(
        _ day: String,
        mergeWindow: TimeInterval,
        dosedTimestamps: Set<TimeInterval>
    ) -> [InferredMealEvent] {
        let daySnapshots = snapshots
            .filter { $0.forDate == day }
            .sorted { $0.timestamp < $1.timestamp }

        guard !daySnapshots.isEmpty else { return [] }

        var events: [InferredMealEvent] = []

        for i in 0 ..< daySnapshots.count {
            let current = daySnapshots[i]
            let prevCarbs: Double
            let prevFat: Double
            let prevProtein: Double
            let prevFiber: Double

            if i == 0 {
                prevCarbs = 0
                prevFat = 0
                prevProtein = 0
                prevFiber = 0
            } else {
                let prev = daySnapshots[i - 1]
                prevCarbs = prev.cumulativeCarbs
                prevFat = prev.cumulativeFat
                prevProtein = prev.cumulativeProtein
                prevFiber = prev.cumulativeFiber
            }

            let dc = current.cumulativeCarbs - prevCarbs
            let df = current.cumulativeFat - prevFat
            let dp = current.cumulativeProtein - prevProtein
            let dfib = current.cumulativeFiber - prevFiber

            guard dc > 1 || df > 1 || dp > 1 else { continue }

            events.append(InferredMealEvent(
                detectedAt: current.latestSampleCreationDate ?? current.timestamp,
                carbsDelta: max(dc, 0),
                fatDelta: max(df, 0),
                proteinDelta: max(dp, 0),
                fiberDelta: max(dfib, 0)
            ))
        }

        return groupIntoMeals(events: events, mergeWindow: mergeWindow, dosedTimestamps: dosedTimestamps)
    }

    // MARK: - Grouping

    private func groupIntoMeals(
        events: [InferredMealEvent],
        mergeWindow: TimeInterval,
        dosedTimestamps: Set<TimeInterval>
    ) -> [InferredMealEvent] {
        guard !events.isEmpty else { return [] }

        var groups: [InferredMealEvent] = []

        for event in events {
            if let lastIdx = groups.indices.last {
                let lastDate = groups[lastIdx].detectedAt
                let withinWindow = event.detectedAt.timeIntervalSince(lastDate) < mergeWindow

                let doseBetween = dosedTimestamps.contains { ts in
                    ts > lastDate.timeIntervalSince1970 &&
                        ts < event.detectedAt.timeIntervalSince1970
                }

                if withinWindow, !doseBetween {
                    let merged = InferredMealEvent(
                        id: groups[lastIdx].id,
                        detectedAt: groups[lastIdx].detectedAt,
                        carbsDelta: groups[lastIdx].carbsDelta + event.carbsDelta,
                        fatDelta: groups[lastIdx].fatDelta + event.fatDelta,
                        proteinDelta: groups[lastIdx].proteinDelta + event.proteinDelta,
                        fiberDelta: groups[lastIdx].fiberDelta + event.fiberDelta
                    )
                    groups[lastIdx] = merged
                    continue
                }
            }
            groups.append(event)
        }

        return groups
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshots = try decoder.decode([NutritionSnapshot].self, from: data)
            pruneOldSnapshots()
        } catch {
            debug(.service, "NutritionSnapshotStore: failed to load snapshots: \(error)")
            snapshots = []
        }
    }

    private func saveToDisk() {
        pruneOldSnapshots()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshots)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debug(.service, "NutritionSnapshotStore: failed to save snapshots: \(error)")
        }
    }

    private func pruneOldSnapshots() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        snapshots.removeAll { $0.timestamp < cutoff }
    }
}

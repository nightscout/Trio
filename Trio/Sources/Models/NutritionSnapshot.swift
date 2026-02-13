import Foundation

// MARK: - Nutrition Snapshot

/// A point-in-time record of cumulative daily macro totals from HealthKit.
/// Snapshots are recorded each time the HealthKit observer fires, and meals
/// are inferred by computing deltas between consecutive snapshots.
struct NutritionSnapshot: Codable, Equatable {
    let timestamp: Date
    let cumulativeCarbs: Double
    let cumulativeFat: Double
    let cumulativeProtein: Double
    /// Calendar day string, e.g. "2026-02-13"
    let forDate: String
}

// MARK: - Inferred Meal Event

/// A meal event inferred from the delta between two consecutive snapshots.
struct InferredMealEvent {
    let detectedAt: Date
    let carbsDelta: Double
    let fatDelta: Double
    let proteinDelta: Double
}

// MARK: - Snapshot Store

/// Persists nutrition snapshots and infers meal events from deltas.
final class NutritionSnapshotStore {
    private var snapshots: [NutritionSnapshot] = []
    private let fileURL: URL
    private let retentionDays: Int = 14
    private let deduplicationWindow: TimeInterval = 2.0

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
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
        let eightHoursAgo = Date().addingTimeInterval(-8 * 60 * 60)
        let today = Self.dateFormatter.string(from: Date())

        // Get today's snapshots sorted by time
        let todaySnapshots = snapshots
            .filter { $0.forDate == today && $0.timestamp >= eightHoursAgo }
            .sorted { $0.timestamp < $1.timestamp }

        guard !todaySnapshots.isEmpty else { return [] }

        // Compute deltas between consecutive snapshots
        // First snapshot uses zero baseline (midnight)
        var events: [InferredMealEvent] = []

        for i in 0 ..< todaySnapshots.count {
            let current = todaySnapshots[i]
            let prevCarbs: Double
            let prevFat: Double
            let prevProtein: Double

            if i == 0 {
                // First snapshot of the day — baseline is zero
                prevCarbs = 0
                prevFat = 0
                prevProtein = 0
            } else {
                let prev = todaySnapshots[i - 1]
                prevCarbs = prev.cumulativeCarbs
                prevFat = prev.cumulativeFat
                prevProtein = prev.cumulativeProtein
            }

            let dc = current.cumulativeCarbs - prevCarbs
            let df = current.cumulativeFat - prevFat
            let dp = current.cumulativeProtein - prevProtein

            // Only create event if at least one macro delta > 1g
            guard dc > 1 || df > 1 || dp > 1 else { continue }

            events.append(InferredMealEvent(
                detectedAt: current.timestamp,
                carbsDelta: max(dc, 0),
                fatDelta: max(df, 0),
                proteinDelta: max(dp, 0)
            ))
        }

        // Group events into meals using merge window + dose boundaries
        return groupIntoMeals(events: events, mergeWindow: mergeWindow, dosedTimestamps: dosedTimestamps)
    }

    /// Current day string.
    static func todayString() -> String {
        dateFormatter.string(from: Date())
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

                // Check if a dose occurred between the last group and this event
                let doseBetween = dosedTimestamps.contains { ts in
                    let doseDate = ts
                    return doseDate > lastDate.timeIntervalSince1970 &&
                        doseDate < event.detectedAt.timeIntervalSince1970
                }

                if withinWindow, !doseBetween {
                    // Merge into current group
                    let merged = InferredMealEvent(
                        detectedAt: groups[lastIdx].detectedAt,
                        carbsDelta: groups[lastIdx].carbsDelta + event.carbsDelta,
                        fatDelta: groups[lastIdx].fatDelta + event.fatDelta,
                        proteinDelta: groups[lastIdx].proteinDelta + event.proteinDelta
                    )
                    groups[lastIdx] = merged
                    continue
                }
            }
            // Start new group
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

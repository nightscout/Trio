import CoreData
import Foundation

/// Saves dose-time snapshots and builds comprehensive meal decision exports
/// with 2h pre-meal + 8h post-meal BG, boluses, temp basals, and loop decisions.
enum MealDecisionExporter {
    private static let snapshotFile = "meal_decision_snapshots.json"
    private static let exportDirectory = "SmartSenseExports"

    // MARK: - Export Time Ranges

    enum ExportRange: String, CaseIterable, Identifiable {
        case oneDay = "1d"
        case threeDays = "3d"
        case sevenDays = "7d"
        case fourteenDays = "14d"
        case thirtyDays = "30d"
        case ninetyDays = "90d"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .oneDay: return "1 Day"
            case .threeDays: return "3 Days"
            case .sevenDays: return "7 Days"
            case .fourteenDays: return "14 Days"
            case .thirtyDays: return "30 Days"
            case .ninetyDays: return "90 Days"
            }
        }

        var days: Int {
            switch self {
            case .oneDay: return 1
            case .threeDays: return 3
            case .sevenDays: return 7
            case .fourteenDays: return 14
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            }
        }

        var startDate: Date {
            Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        }
    }

    // MARK: - Snapshot Persistence

    /// Save a dose-time snapshot. Called from invokeTreatmentsTask() when user commits a dose.
    static func saveSnapshot(_ snapshot: MealDecisionSnapshot) {
        var snapshots = loadAllSnapshots()
        snapshots.append(snapshot)

        // Prune older than 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        snapshots = snapshots.filter { $0.doseTimestamp >= cutoff }

        guard let fileURL = snapshotFileURL() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshots)
            try data.write(to: fileURL, options: .atomic)
            debug(.service, "MealDecisionExporter: saved snapshot (\(snapshots.count) total)")
        } catch {
            debug(.service, "MealDecisionExporter: failed to save snapshot — \(error.localizedDescription)")
        }
    }

    /// Load all persisted snapshots.
    static func loadAllSnapshots() -> [MealDecisionSnapshot] {
        guard let fileURL = snapshotFileURL(),
              FileManager.default.fileExists(atPath: fileURL.path)
        else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([MealDecisionSnapshot].self, from: data)
        } catch {
            debug(.service, "MealDecisionExporter: failed to load snapshots — \(error.localizedDescription)")
            return []
        }
    }

    /// Count of snapshots within a given range.
    static func snapshotCount(for range: ExportRange) -> Int {
        let start = range.startDate
        return loadAllSnapshots().filter { $0.doseTimestamp >= start }.count
    }

    // MARK: - Full Export

    /// Build a comprehensive export with post-meal traces for each snapshot in the range.
    static func buildFullExport(
        range: ExportRange,
        settings: SmartSenseSettings,
        context: NSManagedObjectContext
    ) async -> URL? {
        let startDate = range.startDate
        let snapshots = loadAllSnapshots().filter { $0.doseTimestamp >= startDate }

        guard !snapshots.isEmpty else {
            debug(.service, "MealDecisionExporter: no snapshots in range \(range.label)")
            return nil
        }

        // Build records with post-meal traces
        var records: [MealDecisionRecord] = []
        for snapshot in snapshots {
            let record = await buildRecord(snapshot: snapshot, context: context)
            records.append(record)
        }

        let export = MealDecisionFullExport(
            exportDate: Date(),
            rangeDays: range.days,
            settings: settings,
            records: records
        )

        // Write to file
        guard let exportDir = exportDirectoryURL() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "smartsense_export_\(range.rawValue)_\(formatter.string(from: Date())).json"
        let fileURL = exportDir.appendingPathComponent(filename)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(export)
            try data.write(to: fileURL, options: .atomic)
            debug(
                .service,
                "MealDecisionExporter: export \(filename) — \(records.count) records, \(data.count) bytes"
            )
            return fileURL
        } catch {
            debug(.service, "MealDecisionExporter: export failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Record Builder

    /// Build a single record by querying Core Data for the 2h pre + 8h post window.
    private static func buildRecord(
        snapshot: MealDecisionSnapshot,
        context: NSManagedObjectContext
    ) async -> MealDecisionRecord {
        let doseTime = snapshot.doseTimestamp
        let preStart = doseTime.addingTimeInterval(-2 * 3600)  // 2h before
        let postEnd = min(doseTime.addingTimeInterval(8 * 3600), Date()) // 8h after or now

        async let preBG = fetchBGTrace(from: preStart, to: doseTime, relativeTo: doseTime, context: context)
        async let postBG = fetchBGTrace(from: doseTime, to: postEnd, relativeTo: doseTime, context: context)
        async let boluses = fetchBoluses(from: doseTime, to: postEnd, relativeTo: doseTime, context: context)
        async let tempBasals = fetchTempBasals(from: doseTime, to: postEnd, relativeTo: doseTime, context: context)
        async let loopDecisions = fetchLoopDecisions(from: doseTime, to: postEnd, relativeTo: doseTime, context: context)

        let (pre, post, bols, temps, loops) = await (preBG, postBG, boluses, tempBasals, loopDecisions)

        let summary = computeSummary(snapshot: snapshot, postBG: post, boluses: bols)

        return MealDecisionRecord(
            snapshot: snapshot,
            preMealBGTrace: pre,
            postMealBGTrace: post,
            bolusEvents: bols,
            tempBasalEvents: temps,
            loopDecisions: loops,
            summary: summary
        )
    }

    // MARK: - Core Data Queries

    private static func fetchBGTrace(
        from start: Date, to end: Date, relativeTo doseTime: Date,
        context: NSManagedObjectContext
    ) async -> [BGPoint] {
        await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "GlucoseStored")
            request.predicate = NSPredicate(
                format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

            guard let results = try? context.fetch(request) else { return [] }
            return results.compactMap { obj -> BGPoint? in
                guard let date = obj.value(forKey: "date") as? Date else { return nil }
                let glucose = obj.value(forKey: "glucose") as? Int16 ?? 0
                let direction = obj.value(forKey: "direction") as? String
                return BGPoint(
                    minutesAfterDose: date.timeIntervalSince(doseTime) / 60,
                    glucose: Int(glucose),
                    direction: direction
                )
            }
        }
    }

    private static func fetchBoluses(
        from start: Date, to end: Date, relativeTo doseTime: Date,
        context: NSManagedObjectContext
    ) async -> [BolusPoint] {
        await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BolusStored")
            request.predicate = NSPredicate(
                format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
                start as NSDate, end as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "pumpEvent.timestamp", ascending: true)]

            guard let results = try? context.fetch(request) else { return [] }
            return results.compactMap { bolus -> BolusPoint? in
                guard let pe = bolus.value(forKey: "pumpEvent") as? NSManagedObject,
                      let ts = pe.value(forKey: "timestamp") as? Date
                else { return nil }

                let amount = (bolus.value(forKey: "amount") as? NSDecimalNumber)?.doubleValue ?? 0
                guard amount > 0 else { return nil }

                return BolusPoint(
                    minutesAfterDose: ts.timeIntervalSince(doseTime) / 60,
                    amount: amount,
                    isSMB: bolus.value(forKey: "isSMB") as? Bool ?? false,
                    isExternal: bolus.value(forKey: "isExternal") as? Bool ?? false
                )
            }
        }
    }

    private static func fetchTempBasals(
        from start: Date, to end: Date, relativeTo doseTime: Date,
        context: NSManagedObjectContext
    ) async -> [TempBasalPoint] {
        await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "TempBasalStored")
            request.predicate = NSPredicate(
                format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
                start as NSDate, end as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "pumpEvent.timestamp", ascending: true)]

            guard let results = try? context.fetch(request) else { return [] }
            return results.compactMap { tb -> TempBasalPoint? in
                guard let pe = tb.value(forKey: "pumpEvent") as? NSManagedObject,
                      let ts = pe.value(forKey: "timestamp") as? Date
                else { return nil }

                return TempBasalPoint(
                    minutesAfterDose: ts.timeIntervalSince(doseTime) / 60,
                    rate: (tb.value(forKey: "rate") as? NSDecimalNumber)?.doubleValue ?? 0,
                    durationMinutes: Int(tb.value(forKey: "duration") as? Int16 ?? 0)
                )
            }
        }
    }

    private static func fetchLoopDecisions(
        from start: Date, to end: Date, relativeTo doseTime: Date,
        context: NSManagedObjectContext
    ) async -> [LoopDecisionPoint] {
        await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "OrefDetermination")
            request.predicate = NSPredicate(
                format: "deliverAt >= %@ AND deliverAt <= %@",
                start as NSDate, end as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "deliverAt", ascending: true)]

            guard let results = try? context.fetch(request) else { return [] }
            return results.compactMap { det -> LoopDecisionPoint? in
                guard let date = det.value(forKey: "deliverAt") as? Date else { return nil }
                return LoopDecisionPoint(
                    minutesAfterDose: date.timeIntervalSince(doseTime) / 60,
                    glucose: (det.value(forKey: "glucose") as? NSDecimalNumber)?.doubleValue ?? 0,
                    iob: (det.value(forKey: "iob") as? NSDecimalNumber)?.doubleValue ?? 0,
                    cob: Int(det.value(forKey: "cob") as? Int16 ?? 0),
                    eventualBG: (det.value(forKey: "eventualBG") as? NSDecimalNumber)?.doubleValue ?? 0,
                    insulinReq: (det.value(forKey: "insulinReq") as? NSDecimalNumber)?.doubleValue ?? 0,
                    smbDelivered: (det.value(forKey: "smbToDeliver") as? NSDecimalNumber)?.doubleValue ?? 0,
                    tempBasalRate: (det.value(forKey: "rate") as? NSDecimalNumber)?.doubleValue,
                    sensitivityRatio: (det.value(forKey: "sensitivityRatio") as? NSDecimalNumber)?.doubleValue ?? 1.0
                )
            }
        }
    }

    // MARK: - Summary Computation

    private static func computeSummary(
        snapshot: MealDecisionSnapshot,
        postBG: [BGPoint],
        boluses: [BolusPoint]
    ) -> MealOutcomeSummary? {
        guard !postBG.isEmpty else { return nil }

        let bgValues = postBG.map(\.glucose)
        let peak = postBG.max(by: { $0.glucose < $1.glucose })
        let nadir = postBG.filter { $0.minutesAfterDose > 0 }.min(by: { $0.glucose < $1.glucose })

        let bgAt2h = postBG.first(where: { $0.minutesAfterDose >= 115 && $0.minutesAfterDose <= 125 })?.glucose
        let bgAt4h = postBG.first(where: { $0.minutesAfterDose >= 235 && $0.minutesAfterDose <= 245 })?.glucose

        let totalInsulin = boluses.reduce(0.0) { $0 + $1.amount }

        // Approximate time above/below (5-min intervals)
        let readingInterval = 5.0
        let above180 = Int(Double(bgValues.filter { $0 > 180 }.count) * readingInterval)
        let below70 = Int(Double(bgValues.filter { $0 < 70 }.count) * readingInterval)

        return MealOutcomeSummary(
            carbsEntered: snapshot.totalCarbs,
            recommendedDose: snapshot.recommended,
            userDose: snapshot.userConfirmedDose,
            totalInsulinDelivered: totalInsulin,
            bgAtDose: Int(snapshot.currentBG),
            peakBG: peak?.glucose,
            peakMinutes: peak.map { Int($0.minutesAfterDose) },
            nadirBG: nadir?.glucose,
            nadirMinutes: nadir.map { Int($0.minutesAfterDose) },
            bgAt2h: bgAt2h,
            bgAt4h: bgAt4h,
            timeAbove180Minutes: above180,
            timeBelow70Minutes: below70
        )
    }

    // MARK: - File Helpers

    private static func snapshotFileURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent(snapshotFile)
    }

    private static func exportDirectoryURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = docs.appendingPathComponent(exportDirectory, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

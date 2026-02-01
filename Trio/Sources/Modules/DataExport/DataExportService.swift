import CoreData
import Foundation

final class DataExportService {
    private let context: NSManagedObjectContext

    init() {
        context = CoreDataStack.shared.newTaskContext()
    }

    enum ExportRange: String, CaseIterable, Identifiable {
        case day1 = "Last 24 Hours"
        case days3 = "Last 3 Days"
        case week = "Last 7 Days"
        case month = "Last 30 Days"
        case months3 = "Last 3 Months"

        var id: String { rawValue }

        var startDate: Date {
            switch self {
            case .day1: return Date.oneDayAgo
            case .days3: return Calendar.current.date(byAdding: .day, value: -3, to: Date())!
            case .week: return Date.oneWeekAgo
            case .month: return Date.oneMonthAgo
            case .months3: return Date.threeMonthsAgo
            }
        }
    }

    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func fmt(_ date: Date?) -> String {
        guard let date else { return "" }
        return dateFormatter.string(from: date)
    }

    private func dec(_ val: NSDecimalNumber?) -> String {
        guard let val else { return "" }
        return "\(val)"
    }

    // MARK: - Export All Data

    func exportAll(range: ExportRange) async throws -> URL {
        let startDate = range.startDate
        let endDate = Date()

        let glucoseCSV = try await exportGlucose(start: startDate, end: endDate)
        let carbsCSV = try await exportCarbs(start: startDate, end: endDate)
        let bolusCSV = try await exportBoluses(start: startDate, end: endDate)
        let basalCSV = try await exportTempBasals(start: startDate, end: endDate)
        let determinationsCSV = try await exportDeterminations(start: startDate, end: endDate)
        let tddCSV = try await exportTDD(start: startDate, end: endDate)

        // Build a single combined file with all data sections
        let combined = buildCombinedExport(
            range: range,
            glucose: glucoseCSV,
            carbs: carbsCSV,
            bolus: bolusCSV,
            basal: basalCSV,
            determinations: determinationsCSV,
            tdd: tddCSV
        )

        let fileName = "Trio_Export_\(range.rawValue.replacingOccurrences(of: " ", with: "_")).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        try combined.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

    // MARK: - Glucose

    private func exportGlucose(start: Date, end: Date) async throws -> String {
        let predicate = NSPredicate.predicateForDateBetween(start: start, end: end)
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: predicate,
            key: "date",
            ascending: true
        )

        guard let readings = results as? [GlucoseStored] else { return "date,glucose_mgdl,direction,is_manual\n" }

        var csv = "date,glucose_mgdl,direction,is_manual\n"
        await context.perform {
            for r in readings {
                csv += "\(self.fmt(r.date)),\(r.glucose),\(r.direction ?? ""),\(r.isManual)\n"
            }
        }
        return csv
    }

    // MARK: - Carbs

    private func exportCarbs(start: Date, end: Date) async throws -> String {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.predicateForDateBetween(start: start, end: end),
            NSPredicate(format: "isFPU == NO")
        ])
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: predicate,
            key: "date",
            ascending: true
        )

        guard let entries = results as? [CarbEntryStored] else { return "date,carbs_g,fat_g,protein_g,note\n" }

        var csv = "date,carbs_g,fat_g,protein_g,note\n"
        await context.perform {
            for e in entries {
                let note = (e.note ?? "").replacingOccurrences(of: ",", with: ";")
                csv += "\(self.fmt(e.date)),\(e.carbs),\(e.fat),\(e.protein),\(note)\n"
            }
        }
        return csv
    }

    // MARK: - Boluses

    private func exportBoluses(start: Date, end: Date) async throws -> String {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.predicateForTimestampBetween(start: start, end: end),
            NSPredicate(format: "type == %@", PumpEventStored.EventType.bolus.rawValue)
        ])
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: predicate,
            key: "timestamp",
            ascending: true,
            relationshipKeyPathsForPrefetching: ["bolus"]
        )

        guard let events = results as? [PumpEventStored] else { return "date,amount_units,is_smb,is_external\n" }

        var csv = "date,amount_units,is_smb,is_external\n"
        await context.perform {
            for e in events {
                if let b = e.bolus {
                    csv += "\(self.fmt(e.timestamp)),\(self.dec(b.amount)),\(b.isSMB),\(b.isExternal)\n"
                }
            }
        }
        return csv
    }

    // MARK: - Temp Basals

    private func exportTempBasals(start: Date, end: Date) async throws -> String {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.predicateForTimestampBetween(start: start, end: end),
            NSPredicate(format: "type == %@", PumpEventStored.EventType.tempBasal.rawValue)
        ])
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: predicate,
            key: "timestamp",
            ascending: true,
            relationshipKeyPathsForPrefetching: ["tempBasal"]
        )

        guard let events = results as? [PumpEventStored] else { return "date,rate_uhr,duration_min,type\n" }

        var csv = "date,rate_uhr,duration_min,type\n"
        await context.perform {
            for e in events {
                if let tb = e.tempBasal {
                    csv += "\(self.fmt(e.timestamp)),\(self.dec(tb.rate)),\(tb.duration),\(tb.tempType ?? "")\n"
                }
            }
        }
        return csv
    }

    // MARK: - Determinations (Algorithm Decisions)

    private func exportDeterminations(start: Date, end: Date) async throws -> String {
        let predicate = NSPredicate.predicateForDeliverAtBetween(start: start, end: end)
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: predicate,
            key: "deliverAt",
            ascending: true
        )

        guard let dets = results as? [OrefDetermination] else {
            return "date,glucose,eventual_bg,iob,cob,isf,cr,target,rate,smb,insulin_req,sensitivity_ratio,reason\n"
        }

        var csv = "date,glucose,eventual_bg,iob,cob,isf,cr,target,rate,smb,insulin_req,sensitivity_ratio,reason\n"
        await context.perform {
            for d in dets {
                let reason = (d.reason ?? "").replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
                csv += "\(self.fmt(d.deliverAt))"
                csv += ",\(self.dec(d.glucose))"
                csv += ",\(self.dec(d.eventualBG))"
                csv += ",\(self.dec(d.iob))"
                csv += ",\(d.cob)"
                csv += ",\(self.dec(d.insulinSensitivity))"
                csv += ",\(self.dec(d.carbRatio))"
                csv += ",\(self.dec(d.currentTarget))"
                csv += ",\(self.dec(d.rate))"
                csv += ",\(self.dec(d.smbToDeliver))"
                csv += ",\(self.dec(d.insulinReq))"
                csv += ",\(self.dec(d.sensitivityRatio))"
                csv += ",\"\(reason)\""
                csv += "\n"
            }
        }
        return csv
    }

    // MARK: - TDD

    private func exportTDD(start: Date, end: Date) async throws -> String {
        let predicate = NSPredicate.predicateForDateBetween(start: start, end: end)
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: context,
            predicate: predicate,
            key: "date",
            ascending: true
        )

        guard let tdds = results as? [TDDStored] else {
            return "date,total_units,bolus_units,temp_basal_units,scheduled_basal_units\n"
        }

        var csv = "date,total_units,bolus_units,temp_basal_units,scheduled_basal_units\n"
        await context.perform {
            for t in tdds {
                csv += "\(self.fmt(t.date)),\(self.dec(t.total)),\(self.dec(t.bolus)),\(self.dec(t.tempBasal)),\(self.dec(t.scheduledBasal))\n"
            }
        }
        return csv
    }

    // MARK: - Combined Export

    private func buildCombinedExport(
        range: ExportRange,
        glucose: String,
        carbs: String,
        bolus: String,
        basal: String,
        determinations: String,
        tdd: String
    ) -> String {
        func lineCount(_ csv: String) -> Int { max(0, csv.components(separatedBy: "\n").count - 2) }

        var output = ""

        // Header with metadata
        output += "# Trio Data Export\n"
        output += "# Range: \(range.rawValue)\n"
        output += "# Exported: \(fmt(Date()))\n"
        output += "# Glucose readings: \(lineCount(glucose))\n"
        output += "# Carb entries: \(lineCount(carbs))\n"
        output += "# Boluses: \(lineCount(bolus))\n"
        output += "# Temp basals: \(lineCount(basal))\n"
        output += "# Algorithm determinations: \(lineCount(determinations))\n"
        output += "# TDD records: \(lineCount(tdd))\n"
        output += "# All dates are ISO 8601 UTC. Glucose in mg/dL. Insulin in Units. Carbs in grams.\n"
        output += "#\n"

        output += "\n### GLUCOSE READINGS ###\n"
        output += glucose

        output += "\n### CARB ENTRIES ###\n"
        output += carbs

        output += "\n### INSULIN BOLUSES ###\n"
        output += bolus

        output += "\n### TEMP BASAL RATES ###\n"
        output += basal

        output += "\n### ALGORITHM DETERMINATIONS ###\n"
        output += determinations

        output += "\n### TOTAL DAILY DOSE ###\n"
        output += tdd

        return output
    }
}

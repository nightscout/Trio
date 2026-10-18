import CoreData
import Foundation

struct DeterminationSnapshot: Codable, Equatable {
    var id: UUID?
    var deliverAt: Date?
    var timestamp: Date?
    var timestampEnacted: Date?
    var enacted: Bool
    var received: Bool
    var isUploadedToNS: Bool
    var glucose: Decimal?
    var iob: Decimal?
    var cob: Int16
    var insulinSensitivity: Decimal?
    var sensitivityRatio: Decimal?
    var currentTarget: Decimal?
    var eventualBG: Decimal?
    var rate: Decimal?
    var duration: Decimal?
    var temp: String?
    var smbToDeliver: Decimal?
    var insulinReq: Decimal?
    var carbRatio: Decimal?
    var carbsRequired: Int16
    var scheduledBasal: Decimal?
    var reservoir: Decimal?
    var threshold: Decimal?
    var expectedDelta: Decimal?
    var minDelta: Decimal?
    var reason: String?
    var forecasts: [String: [Int32]]

    var markdown: String {
        let fields = [
            "\(ReportFormatting.timestamp(deliverAt ?? timestamp)) \(enacted ? "enacted" : "suggested")",
            "glucose \(ReportFormatting.number(glucose))",
            "iob \(ReportFormatting.number(iob))",
            "cob \(cob)",
            "isf \(ReportFormatting.number(insulinSensitivity))",
            "sensitivityRatio \(ReportFormatting.number(sensitivityRatio))",
            "rate \(ReportFormatting.number(rate)) for \(ReportFormatting.number(duration)) min",
            "smbToDeliver \(ReportFormatting.number(smbToDeliver))",
            "eventualBG \(ReportFormatting.number(eventualBG))",
            "target \(ReportFormatting.number(currentTarget))"
        ]
        let fence = ReportFormatting.fenced(reason ?? "").components(separatedBy: "\n").map { "  \($0)" }
        return (["- " + fields.joined(separator: " · ")] + fence).joined(separator: "\n")
    }

    static func markdown(for snapshots: [DeterminationSnapshot], limit: Int = 100) -> String {
        guard !snapshots.isEmpty else { return "_No determinations in window_" }
        let newestFirst = snapshots.sorted { ($0.deliverAt ?? .distantPast) > ($1.deliverAt ?? .distantPast) }
        var lines = ["\(snapshots.count) runs in window, newest first. All runs with forecasts in Determinations.json."]
        if snapshots.count > limit {
            lines.append("Showing the newest \(limit).")
        }
        lines.append("")
        lines += newestFirst.prefix(limit).map(\.markdown)
        return lines.joined(separator: "\n")
    }
}

extension DeterminationSnapshot {
    init(_ determination: OrefDetermination) {
        var forecasts: [String: [Int32]] = [:]
        for forecast in determination.forecasts ?? [] {
            let values = (forecast.forecastValues ?? []).sorted { $0.index < $1.index }.map(\.value)
            forecasts[forecast.type ?? "unknown", default: []] += values
        }
        self.init(
            id: determination.id,
            deliverAt: determination.deliverAt,
            timestamp: determination.timestamp,
            timestampEnacted: determination.timestampEnacted,
            enacted: determination.enacted,
            received: determination.received,
            isUploadedToNS: determination.isUploadedToNS,
            glucose: determination.glucose?.decimalValue,
            iob: determination.iob?.decimalValue,
            cob: determination.cob,
            insulinSensitivity: determination.insulinSensitivity?.decimalValue,
            sensitivityRatio: determination.sensitivityRatio?.decimalValue,
            currentTarget: determination.currentTarget?.decimalValue,
            eventualBG: determination.eventualBG?.decimalValue,
            rate: determination.rate?.decimalValue,
            duration: determination.duration?.decimalValue,
            temp: determination.temp,
            smbToDeliver: determination.smbToDeliver?.decimalValue,
            insulinReq: determination.insulinReq?.decimalValue,
            carbRatio: determination.carbRatio?.decimalValue,
            carbsRequired: determination.carbsRequired,
            scheduledBasal: determination.scheduledBasal?.decimalValue,
            reservoir: determination.reservoir?.decimalValue,
            threshold: determination.threshold?.decimalValue,
            expectedDelta: determination.expectedDelta?.decimalValue,
            minDelta: determination.minDelta?.decimalValue,
            reason: determination.reason,
            forecasts: forecasts
        )
    }
}

struct DeterminationsSection: DiagnosticReportSection {
    let title = "Determinations"
    let order = 50
    var makeContext: () -> NSManagedObjectContext = { CoreDataStack.shared.newTaskContext() }

    func render(window: DateInterval, into directory: URL) async -> String {
        let context = makeContext()
        context.name = "diagnosticReportDeterminations"
        let snapshots: [DeterminationSnapshot]
        do {
            snapshots = try await context.perform {
                let request: NSFetchRequest<OrefDetermination> = OrefDetermination.fetchRequest()
                request.predicate = NSPredicate(
                    format: "deliverAt >= %@ AND deliverAt <= %@",
                    window.start as NSDate,
                    window.end as NSDate
                )
                request.sortDescriptors = [NSSortDescriptor(key: "deliverAt", ascending: false)]
                request.relationshipKeyPathsForPrefetching = ["forecasts", "forecasts.forecastValues"]
                request.fetchBatchSize = 100
                return try context.fetch(request).map(DeterminationSnapshot.init)
            }
        } catch {
            return "_Determinations could not be fetched: \(error.localizedDescription)_"
        }

        let encoder = JSONCoding.encoder
        encoder.outputFormatting.insert(.sortedKeys)
        do {
            try encoder.encode(snapshots).write(to: directory.appendingPathComponent("Determinations.json"))
        } catch {
            warning(.service, "Could not write determinations for the report: \(error)")
        }
        return DeterminationSnapshot.markdown(for: snapshots)
    }
}

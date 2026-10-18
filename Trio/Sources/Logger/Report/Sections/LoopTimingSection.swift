import CoreData
import Foundation

struct LoopTimingSection: DiagnosticReportSection {
    let title = "Loop timing"
    let order = 60
    var makeContext: () -> NSManagedObjectContext = { CoreDataStack.shared.newTaskContext() }

    private static let limit = 50

    private struct Run {
        let start: Date?
        let end: Date?
        let seconds: Double
        let status: String
    }

    func render(window: DateInterval, into _: URL) async -> String {
        let context = makeContext()
        context.name = "diagnosticReportLoopTiming"
        let runs: [Run]
        do {
            runs = try await context.perform {
                let request: NSFetchRequest<LoopStatRecord> = LoopStatRecord.fetchRequest()
                request.predicate = NSPredicate(
                    format: "start >= %@ AND start <= %@",
                    window.start as NSDate,
                    window.end as NSDate
                )
                request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: false)]
                request.fetchLimit = Self.limit
                return try context.fetch(request).map { record in
                    // Stored duration is in minutes
                    let seconds = record.start.flatMap { start in record.end.map { $0.timeIntervalSince(start) } }
                        ?? record.duration * 60
                    return Run(start: record.start, end: record.end, seconds: seconds, status: record.loopStatus ?? "-")
                }
            }
        } catch {
            return "_Loop statistics could not be fetched: \(error.localizedDescription)_"
        }
        guard !runs.isEmpty else { return "_No loop runs in window_" }

        let durations = runs.map(\.seconds).sorted()
        var lines = [
            "Last \(runs.count) runs, newest first. Median \(ReportFormatting.number(Self.median(durations))) s, max \(ReportFormatting.number(durations.last ?? 0)) s.",
            ""
        ]
        lines += runs.map {
            "- \(ReportFormatting.timestamp($0.start)) → \(ReportFormatting.timestamp($0.end)) · \(ReportFormatting.number($0.seconds)) s · \($0.status.replacingOccurrences(of: "\n", with: " "))"
        }
        return lines.joined(separator: "\n")
    }

    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

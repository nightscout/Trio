import CoreData
import Foundation

struct NightscoutSection: DiagnosticReportSection {
    let title = "Nightscout"
    let order = 70
    let settingsManager: SettingsManager?
    let keychain: Keychain?
    let reachabilityManager: ReachabilityManager?
    var makeContext: () -> NSManagedObjectContext = { CoreDataStack.shared.newTaskContext() }

    func render(window: DateInterval, into _: URL) async -> String {
        let url: String? = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.urlKey)
        let secret: String? = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        let settings = settingsManager?.settings
        var lines = [
            "- URL configured: \(Self.yesNo(url?.isEmpty == false))",
            "- Host: \(url.flatMap { URL(string: $0)?.host } ?? "-")",
            "- API secret configured: \(Self.yesNo(secret?.isEmpty == false))",
            "- Upload enabled: \(Self.yesNo(settings?.isUploadEnabled))",
            "- Download enabled: \(Self.yesNo(settings?.isDownloadEnabled))",
            "- Upload glucose: \(Self.yesNo(settings?.uploadGlucose))",
            "- Upload CGM sensor states: \(Self.yesNo(settings?.uploadCGMSensorStates))",
            "- Nightscout as CGM: \(Self.yesNo(settings.map { $0.cgm == .nightscout }))",
            "- Network reachable: \(Self.yesNo(reachabilityManager?.isReachable))"
        ]

        let context = makeContext()
        context.name = "diagnosticReportNightscout"
        let start = window.start as NSDate
        let end = window.end as NSDate
        let summary: [String] = await context.perform {
            func pending(_ entity: String, dateKey: String) -> String {
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
                request.predicate = NSPredicate(
                    format: "%K >= %@ AND %K <= %@ AND isUploadedToNS == NO",
                    dateKey, start, dateKey, end
                )
                return (try? context.count(for: request)).map(String.init) ?? "-"
            }
            let lastUploaded: NSFetchRequest<OrefDetermination> = OrefDetermination.fetchRequest()
            lastUploaded.predicate = NSPredicate(format: "isUploadedToNS == YES")
            lastUploaded.sortDescriptors = [NSSortDescriptor(key: "deliverAt", ascending: false)]
            lastUploaded.fetchLimit = 1
            let lastDate = (try? context.fetch(lastUploaded))?.first?.deliverAt
            return [
                "- Newest uploaded determination: \(ReportFormatting.timestamp(lastDate))",
                "- Not uploaded in window: determinations \(pending("OrefDetermination", dateKey: "deliverAt")), glucose \(pending("GlucoseStored", dateKey: "date")), carbs \(pending("CarbEntryStored", dateKey: "date")), pump events \(pending("PumpEventStored", dateKey: "timestamp"))"
            ]
        }
        lines += summary
        lines += ["", "Trio does not record individual upload or download results; see the nightscout lines in AppLog.txt."]
        return lines.joined(separator: "\n")
    }

    private static func yesNo(_ value: Bool?) -> String {
        value.map { $0 ? "yes" : "no" } ?? "-"
    }
}

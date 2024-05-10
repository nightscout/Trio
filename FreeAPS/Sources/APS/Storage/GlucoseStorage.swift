import AVFAudio
import CoreData
import Foundation
import SwiftDate
import SwiftUI
import Swinject

protocol GlucoseStorage {
    func storeGlucose(_ glucose: [BloodGlucose])
    func syncDate() -> Date
    func filterTooFrequentGlucose(_ glucose: [BloodGlucose], at: Date) -> [BloodGlucose]
    func lastGlucoseDate() -> Date
    func isGlucoseFresh() -> Bool
    func nightscoutGlucoseNotUploaded() -> [BloodGlucose]
    func nightscoutCGMStateNotUploaded() -> [NigtscoutTreatment]
    func nightscoutManualGlucoseNotUploaded() -> [NigtscoutTreatment]
    var alarm: GlucoseAlarm? { get }
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    let coredataContext = CoreDataStack.shared.backgroundContext

    private enum Config {
        static let filterTime: TimeInterval = 3.5 * 60
    }

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.maximumFractionDigits = 1
        }
        formatter.decimalSeparator = "."
        return formatter
    }

    func storeGlucose(_ glucose: [BloodGlucose]) {
        processQueue.sync {
            debug(.deviceManager, "start storage glucose")

            self.coredataContext.perform {
                let datesToCheck: Set<Date?> = Set(glucose.compactMap { $0.dateString as Date? })
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = GlucoseStored.fetchRequest()
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "date IN %@", datesToCheck),
                    NSPredicate.predicateForOneDayAgo
                ])
                fetchRequest.propertiesToFetch = ["date"]
                fetchRequest.resultType = .dictionaryResultType

                var existingDates = Set<Date>()
                do {
                    let results = try self.coredataContext.fetch(fetchRequest) as? [NSDictionary]
                    existingDates = Set(results?.compactMap({ $0["date"] as? Date }) ?? [])
                } catch {
                    debugPrint("Failed to fetch existing glucose dates: \(error)")
                }

                var filteredGlucose = glucose.filter { !existingDates.contains($0.dateString) }

                let batchInsert = NSBatchInsertRequest(entity: GlucoseStored.entity(), dictionaryHandler: { (dict) -> Bool in
                    guard !filteredGlucose.isEmpty else {
                        return true // Stop if there are no more items
                    }
                    let glucoseEntry = filteredGlucose.removeFirst()
                    dict["id"] = UUID()
                    dict["glucose"] = Int16(glucoseEntry.glucose ?? 0)
                    dict["date"] = glucoseEntry.dateString
                    dict["direction"] = glucoseEntry.direction?.symbol
                    return false // Continue processing
                })

                do {
                    try self.coredataContext.execute(batchInsert)
                    debugPrint("Glucose Storage: saved glucose to core data")
                } catch {
                    debugPrint("Glucose Storage: failed to save glucose to core data: \(error)")
                }
            }
        }
    }

    func syncDate() -> Date {
        //  TODO: - proof logic here!
        fetchGlucose().first?.date ?? .distantPast
    }

    func lastGlucoseDate() -> Date {
        fetchGlucose().first?.date ?? .distantPast
    }

    func isGlucoseFresh() -> Bool {
        Date().timeIntervalSince(lastGlucoseDate()) <= Config.filterTime
    }

    func filterTooFrequentGlucose(_ glucose: [BloodGlucose], at date: Date) -> [BloodGlucose] {
        var lastDate = date
        var filtered: [BloodGlucose] = []
        let sorted = glucose.sorted { $0.date < $1.date }

        for entry in sorted {
            guard entry.dateString.addingTimeInterval(-Config.filterTime) > lastDate else {
                continue
            }
            filtered.append(entry)
            lastDate = entry.dateString
        }

        return filtered
    }

    // MARK: - fetching non manual Glucose, manual Glucose and the last glucose value

    // TODO: -optimize this bullshit here...I would love to use the async/await pattern, but its simply not possible because you would need to change all the calls of the following functions and make them async...same shit with the NSAsynchronousFetchRequest
    /// its all done on a background thread and on a separate queue so hopefully its not too heavy
    /// also tried this but here again you need to make everything asynchronous...
    ///  let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    /// privateContext.parent = coredataContext /// merges changes to the core data context
    private func fetchGlucose() -> [GlucoseStored] {
        do {
            debugPrint("OpenAPS: \(#function) \(DebuggingIdentifiers.succeeded) fetched glucose")
            return try coredataContext.fetch(GlucoseStored.fetch(
                NSPredicate.predicateForOneDayAgo,
                ascending: false,
                fetchLimit: 288,
                batchSize: 50
            ))
        } catch {
            debugPrint("OpenAPS: \(#function) \(DebuggingIdentifiers.failed) failed to fetch glucose")
            return []
        }
    }

    private func fetchLatestGlucose() -> GlucoseStored? {
        do {
            debugPrint("Glucose Storage: \(#function) \(DebuggingIdentifiers.succeeded) fetched glucose")
            return try coredataContext.fetch(GlucoseStored.fetch(
                NSPredicate.predicateFor20MinAgo,
                ascending: false,
                fetchLimit: 1
            )).first
        } catch {
            debugPrint("Glucose Storage: \(#function) \(DebuggingIdentifiers.failed) failed to fetch glucose")
            return nil
        }
    }

    private func fetchAndProcessManualGlucose() -> [BloodGlucose] {
        do {
            let fetchedResults = try coredataContext.fetch(GlucoseStored.fetch(
                NSPredicate.manualGlucose,
                ascending: false,
                fetchLimit: 288,
                batchSize: 50
            ))
            debugPrint("Glucose Storage: \(#function) \(DebuggingIdentifiers.succeeded) fetched manual glucose")
            let glucoseArray = fetchedResults.map { result in
                BloodGlucose(
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    type: ""
                )
            }
            return glucoseArray
        } catch {
            debugPrint("Glucose Storage: \(#function) \(DebuggingIdentifiers.failed) failed to fetch manual glucose")
            return []
        }
    }

    private func fetchAndProcessGlucose() -> [BloodGlucose] {
        do {
            let results = try coredataContext.fetch(GlucoseStored.fetch(
                NSPredicate.predicateForOneDayAgo,
                ascending: false,
                fetchLimit: 288,
                batchSize: 50
            ))

            debugPrint("Glucose Storage: \(#function) \(DebuggingIdentifiers.succeeded) fetched glucose")

            let glucoseArray = results.map { result in
                BloodGlucose(
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    type: ""
                )
            }
            return glucoseArray
        } catch {
            debugPrint("Glucose Storage: \(#function) \(DebuggingIdentifiers.failed) failed to fetch glucose")
            return []
        }
    }

    func nightscoutGlucoseNotUploaded() -> [BloodGlucose] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedGlucose, as: [BloodGlucose].self) ?? []
        let recentGlucose = fetchAndProcessGlucose()

        return Array(Set(recentGlucose).subtracting(Set(uploaded)))
    }

    func nightscoutCGMStateNotUploaded() -> [NigtscoutTreatment] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedCGMState, as: [NigtscoutTreatment].self) ?? []
        let recent = storage.retrieve(OpenAPS.Monitor.cgmState, as: [NigtscoutTreatment].self) ?? []
        return Array(Set(recent).subtracting(Set(uploaded)))
    }

    func nightscoutManualGlucoseNotUploaded() -> [NigtscoutTreatment] {
        let uploaded = (storage.retrieve(OpenAPS.Nightscout.uploadedGlucose, as: [BloodGlucose].self) ?? [])
            .filter({ $0.type == GlucoseType.manual.rawValue })

        let recent = fetchAndProcessManualGlucose()
        let filtered = Array(Set(recent).subtracting(Set(uploaded)))
        let manualReadings = filtered.map { item -> NigtscoutTreatment in
            NigtscoutTreatment(
                duration: nil, rawDuration: nil, rawRate: nil, absolute: nil, rate: nil, eventType: .capillaryGlucose,
                createdAt: item.dateString, enteredBy: "iAPS", bolus: nil, insulin: nil, notes: "iAPS User", carbs: nil,
                fat: nil,
                protein: nil, foodType: nil, targetTop: nil, targetBottom: nil, glucoseType: "Manual",
                glucose: settingsManager.settings
                    .units == .mgdL ? (glucoseFormatter.string(from: Int(item.glucose ?? 100) as NSNumber) ?? "")
                    : (glucoseFormatter.string(from: Decimal(item.glucose ?? 100).asMmolL as NSNumber) ?? ""),
                units: settingsManager.settings.units == .mmolL ? "mmol" : "mg/dl"
            )
        }
        return manualReadings
    }

    var alarm: GlucoseAlarm? {
        /// glucose can not be older than 20 minutes due to the predicate in the fetch request
        guard let glucose = fetchLatestGlucose() else { return nil }

        let glucoseValue = glucose.glucose

        if Decimal(glucoseValue) <= settingsManager.settings.lowGlucose {
            return .low
        }

        if Decimal(glucoseValue) >= settingsManager.settings.highGlucose {
            return .high
        }

        return nil
    }
}

protocol GlucoseObserver {
    func glucoseDidUpdate(_ glucose: [BloodGlucose])
}

enum GlucoseAlarm {
    case high
    case low

    var displayName: String {
        switch self {
        case .high:
            return NSLocalizedString("LOWALERT!", comment: "LOWALERT!")
        case .low:
            return NSLocalizedString("HIGHALERT!", comment: "HIGHALERT!")
        }
    }
}

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
    func fetchGlucose() -> [GlucoseStored]
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    let coredataContext = CoreDataStack.shared.newTaskContext()

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
            debug(.deviceManager, "Start storage of glucose data")

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

                // prepare batch insert
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
                batchInsert.resultType = .objectIDs

                // process batch insert and merge changes to context
                do {
                    if let result = try self.coredataContext.execute(batchInsert) as? NSBatchInsertResult,
                       let objectIDs = result.result as? [NSManagedObjectID]
                    {
                        // Merges the insertions into the context
                        NSManagedObjectContext.mergeChanges(
                            fromRemoteContextSave: [NSInsertedObjectsKey: objectIDs],
                            into: [self.coredataContext]
                        )
                        debugPrint(
                            "Glucose Storage: \(#function) \(DebuggingIdentifiers.succeeded) saved glucose to Core Data and merged changes into coreDataContext"
                        )
                    }
                } catch {
                    debugPrint(
                        "Glucose Storage: \(#function) \(DebuggingIdentifiers.failed) failed to execute batch insert or merge changes: \(error)"
                    )
                }

                debug(.deviceManager, "start storage cgmState")
                self.storage.transaction { storage in
                    let file = OpenAPS.Monitor.cgmState
                    var treatments = storage.retrieve(file, as: [NigtscoutTreatment].self) ?? []
                    var updated = false
                    for x in glucose {
                        debug(.deviceManager, "storeGlucose \(x)")
                        guard let sessionStartDate = x.sessionStartDate else {
                            continue
                        }
                        if let lastTreatment = treatments.last,
                           let createdAt = lastTreatment.createdAt,
                           // When a new Dexcom sensor is started, it produces multiple consequetive
                           // startDates. Disambiguate them by only allowing a session start per minute.
                           abs(createdAt.timeIntervalSince(sessionStartDate)) < TimeInterval(60)
                        {
                            continue
                        }
                        var notes = ""
                        if let t = x.transmitterID {
                            notes = t
                        }
                        if let a = x.activationDate {
                            notes = "\(notes) activated on \(a)"
                        }
                        let treatment = NigtscoutTreatment(
                            duration: nil,
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: nil,
                            rate: nil,
                            eventType: .nsSensorChange,
                            createdAt: sessionStartDate,
                            enteredBy: NigtscoutTreatment.local,
                            bolus: nil,
                            insulin: nil,
                            notes: notes,
                            carbs: nil,
                            fat: nil,
                            protein: nil,
                            targetTop: nil,
                            targetBottom: nil
                        )
                        debug(.deviceManager, "CGM sensor change \(treatment)")
                        treatments.append(treatment)
                        updated = true
                    }
                    if updated {
                        // We have to keep quite a bit of history as sensors start only every 10 days.
                        storage.save(
                            treatments.filter
                                { $0.createdAt != nil && $0.createdAt!.addingTimeInterval(30.days.timeInterval) > Date() },
                            as: file
                        )
                    }
                }
            }
        }
    }

    func syncDate() -> Date {
        let fr = GlucoseStored.fetchRequest()
        fr.predicate = NSPredicate.predicateForOneDayAgo
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
        fr.fetchLimit = 1

        var date: Date?
        coredataContext.performAndWait {
            do {
                let results = try self.coredataContext.fetch(fr)
                date = results.first?.date
            } catch let error as NSError {
                print("Fetch error: \(DebuggingIdentifiers.failed) \(error.localizedDescription), \(error.userInfo)")
            }
        }

        return date ?? .distantPast
    }

    func lastGlucoseDate() -> Date {
        let fr = GlucoseStored.fetchRequest()
        fr.predicate = NSPredicate.predicateForOneDayAgo
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
        fr.fetchLimit = 1

        var date: Date?
        coredataContext.performAndWait {
            do {
                let results = try self.coredataContext.fetch(fr)
                date = results.first?.date
            } catch let error as NSError {
                print("Fetch error: \(DebuggingIdentifiers.failed) \(error.localizedDescription), \(error.userInfo)")
            }
        }

        return date ?? .distantPast
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
    ///
    func fetchGlucose() -> [GlucoseStored] {
        let predicate = NSPredicate.predicateForOneDayAgo
        return CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: 288,
            batchSize: 50
        )
    }

    func fetchManualGlucose() -> [GlucoseStored] {
        let predicate = NSPredicate.manualGlucose
        return CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: 288,
            batchSize: 50
        )
    }

    func fetchLatestGlucose() -> GlucoseStored? {
        let predicate = NSPredicate.predicateFor20MinAgo
        return CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: 1
        ).first
    }

    private func processManualGlucose() -> [BloodGlucose] {
        coredataContext.performAndWait {
            let fetchedResults = fetchManualGlucose()
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
        }
    }

    private func processGlucose() -> [BloodGlucose] {
        coredataContext.performAndWait {
            let results = self.fetchGlucose()
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
        }
    }

    func nightscoutGlucoseNotUploaded() -> [BloodGlucose] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedGlucose, as: [BloodGlucose].self) ?? []
        let recentGlucose = processGlucose()

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

        let recent = processManualGlucose()
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
        coredataContext.performAndWait {
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

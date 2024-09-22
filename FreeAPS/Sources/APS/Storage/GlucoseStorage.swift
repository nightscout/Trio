import AVFAudio
import Combine
import CoreData
import Foundation
import LoopKit
import SwiftDate
import SwiftUI
import Swinject

protocol GlucoseStorage {
    var updatePublisher: AnyPublisher<Void, Never> { get }
    func storeGlucose(_ glucose: [BloodGlucose])
    func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool
    func syncDate() -> Date
    func filterTooFrequentGlucose(_ glucose: [BloodGlucose], at: Date) -> [BloodGlucose]
    func lastGlucoseDate() -> Date
    func isGlucoseFresh() -> Bool
    func getGlucoseNotYetUploadedToNightscout() async -> [BloodGlucose]
    func getCGMStateNotYetUploadedToNightscout() async -> [NightscoutTreatment]
    func getManualGlucoseNotYetUploadedToNightscout() async -> [NightscoutTreatment]
    func getGlucoseNotYetUploadedToHealth() async -> [BloodGlucose]
    func getManualGlucoseNotYetUploadedToHealth() async -> [BloodGlucose]
    func getGlucoseNotYetUploadedToTidepool() async -> [StoredGlucoseSample]
    func getManualGlucoseNotYetUploadedToTidepool() async -> [StoredGlucoseSample]
    var alarm: GlucoseAlarm? { get }
    func deleteGlucose(_ treatmentObjectID: NSManagedObjectID) async
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    let coredataContext = CoreDataStack.shared.newTaskContext()

    private let updateSubject = PassthroughSubject<Void, Never>()

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

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
                let batchInsert = NSBatchInsertRequest(
                    entity: GlucoseStored.entity(),
                    managedObjectHandler: { (managedObject: NSManagedObject) -> Bool in
                        guard let glucoseEntry = managedObject as? GlucoseStored, !filteredGlucose.isEmpty else {
                            return true // Stop if there are no more items
                        }
                        let entry = filteredGlucose.removeFirst()
                        glucoseEntry.id = UUID()
                        glucoseEntry.glucose = Int16(entry.glucose ?? 0)
                        glucoseEntry.date = entry.dateString
                        glucoseEntry.direction = entry.direction?.rawValue
                        glucoseEntry.isUploadedToNS = false /// the value is not uploaded to NS (yet)
                        glucoseEntry.isUploadedToHealth = false /// the value is not uploaded to Health (yet)
                        glucoseEntry.isUploadedToTidepool = false /// the value is not uploaded to Tidepool (yet)
                        return false // Continue processing
                    }
                )

                // process batch insert
                do {
                    try self.coredataContext.execute(batchInsert)

                    // Notify subscribers that there is a new glucose value
                    // We need to do this because the due to the batch insert there is no ManagedObjectContext notification
                    self.updateSubject.send(())
                } catch {
                    debugPrint(
                        "Glucose Storage: \(#function) \(DebuggingIdentifiers.failed) failed to execute batch insert: \(error)"
                    )
                }

                debug(.deviceManager, "start storage cgmState")
                self.storage.transaction { storage in
                    let file = OpenAPS.Monitor.cgmState
                    var treatments = storage.retrieve(file, as: [NightscoutTreatment].self) ?? []
                    var updated = false
                    for x in glucose {
                        debug(.deviceManager, "storeGlucose \(x)")
                        guard let sessionStartDate = x.sessionStartDate else {
                            continue
                        }
                        if let lastTreatment = treatments.last,
                           let createdAt = lastTreatment.createdAt,
                           // When a new Dexcom sensor is started, it produces multiple consecutive
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
                        let treatment = NightscoutTreatment(
                            duration: nil,
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: nil,
                            rate: nil,
                            eventType: .nsSensorChange,
                            createdAt: sessionStartDate,
                            enteredBy: NightscoutTreatment.local,
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

    func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool {
        guard let glucoseDate = glucoseDate else { return false }
        return glucoseDate > Date().addingTimeInterval(-6 * 60)
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

    // Fetch glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of BloodGlucose to ensure the correct format for the NS Upload
    func getGlucoseNotYetUploadedToNightscout() async -> [BloodGlucose] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.glucoseNotYetUploadedToNightscout,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        guard let fetchedResults = results as? [GlucoseStored] else { return [] }

        return await coredataContext.perform {
            return fetchedResults.map { result in
                BloodGlucose(
                    _id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }
        }
    }

    // Fetch manual glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of NightscoutTreatment to ensure the correct format for the NS Upload
    func getManualGlucoseNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.manualGlucoseNotYetUploadedToNightscout,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        guard let fetchedResults = results as? [GlucoseStored] else { return [] }

        return await coredataContext.perform {
            return fetchedResults.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .capillaryGlucose,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.manual,
                    bolus: nil,
                    insulin: nil,
                    notes: "Trio User",
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    foodType: nil,
                    targetTop: nil,
                    targetBottom: nil,
                    glucoseType: "Manual",
                    glucose: self.settingsManager.settings
                        .units == .mgdL ? (self.glucoseFormatter.string(from: Int(result.glucose) as NSNumber) ?? "")
                        : (self.glucoseFormatter.string(from: Decimal(result.glucose).asMmolL as NSNumber) ?? ""),
                    units: self.settingsManager.settings.units == .mmolL ? "mmol" : "mg/dl",
                    id: result.id?.uuidString
                )
            }
        }
    }

    func getCGMStateNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        async let alreadyUploaded: [NightscoutTreatment] = storage
            .retrieveAsync(OpenAPS.Nightscout.uploadedCGMState, as: [NightscoutTreatment].self) ?? []
        async let allValues: [NightscoutTreatment] = storage
            .retrieveAsync(OpenAPS.Monitor.cgmState, as: [NightscoutTreatment].self) ?? []

        let (alreadyUploadedValues, allValuesSet) = await (alreadyUploaded, allValues)
        return Array(Set(allValuesSet).subtracting(Set(alreadyUploadedValues)))
    }

    // Fetch glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of BloodGlucose to ensure the correct format for the NS Upload
    func getGlucoseNotYetUploadedToHealth() async -> [BloodGlucose] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.glucoseNotYetUploadedToHealth,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        guard let fetchedResults = results as? [GlucoseStored] else { return [] }

        return await coredataContext.perform {
            return fetchedResults.map { result in
                BloodGlucose(
                    _id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }
        }
    }

    // Fetch manual glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of NightscoutTreatment to ensure the correct format for the NS Upload
    func getManualGlucoseNotYetUploadedToHealth() async -> [BloodGlucose] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.manualGlucoseNotYetUploadedToHealth,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        guard let fetchedResults = results as? [GlucoseStored] else { return [] }

        return await coredataContext.perform {
            return fetchedResults.map { result in
                BloodGlucose(
                    _id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }
        }
    }

    // Fetch glucose that is not uploaded to Tidepool yet
    /// - Returns: Array of StoredGlucoseSample to ensure the correct format for Tidepool upload
    func getGlucoseNotYetUploadedToTidepool() async -> [StoredGlucoseSample] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.glucoseNotYetUploadedToTidepool,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        guard let fetchedResults = results as? [GlucoseStored] else { return [] }

        return await coredataContext.perform {
            return fetchedResults.map { result in
                BloodGlucose(
                    _id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }.map { $0.convertStoredGlucoseSample(device: nil) }
        }
    }

    // Fetch manual glucose that is not uploaded to Tidepool yet
    /// - Returns: Array of StoredGlucoseSample to ensure the correct format for the Tidepool upload
    func getManualGlucoseNotYetUploadedToTidepool() async -> [StoredGlucoseSample] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.manualGlucoseNotYetUploadedToTidepool,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        guard let fetchedResults = results as? [GlucoseStored] else { return [] }

        return await coredataContext.perform {
            return fetchedResults.map { result in
                BloodGlucose(
                    _id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }.map { $0.convertStoredGlucoseSample(device: nil) }
        }
    }

    func deleteGlucose(_ treatmentObjectID: NSManagedObjectID) async {
        let taskContext = CoreDataStack.shared.newTaskContext()
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "deleteGlucose"

        await taskContext.perform {
            do {
                let result = try taskContext.existingObject(with: treatmentObjectID) as? GlucoseStored

                guard let glucoseToDelete = result else {
                    debugPrint("Data Table State: \(#function) \(DebuggingIdentifiers.failed) glucose not found in core data")
                    return
                }

                taskContext.delete(glucoseToDelete)

                guard taskContext.hasChanges else { return }
                try taskContext.save()
                debugPrint("\(#file) \(#function) \(DebuggingIdentifiers.succeeded) deleted glucose from core data")
            } catch {
                debugPrint(
                    "\(#file) \(#function) \(DebuggingIdentifiers.failed) error while deleting glucose from core data: \(error.localizedDescription)"
                )
            }
        }
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

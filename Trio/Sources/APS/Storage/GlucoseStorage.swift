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
    func storeGlucose(_ glucose: [BloodGlucose]) async throws
    func addManualGlucose(glucose: Int)
    func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool
    func syncDate() -> Date
    func filterTooFrequentGlucose(_ glucose: [BloodGlucose], at: Date) -> [BloodGlucose]
    func lastGlucoseDate() -> Date
    func isGlucoseFresh() -> Bool
    func getGlucoseNotYetUploadedToNightscout() async throws -> [BloodGlucose]
    func getCGMStateNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getManualGlucoseNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose]
    func getManualGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose]
    func getGlucoseNotYetUploadedToTidepool() async throws -> [StoredGlucoseSample]
    func getManualGlucoseNotYetUploadedToTidepool() async throws -> [StoredGlucoseSample]
    var alarm: GlucoseAlarm? { get }
    func deleteGlucose(_ treatmentObjectID: NSManagedObjectID) async
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    private let updateSubject = PassthroughSubject<Void, Never>()

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    private enum Config {
        static let filterTime: TimeInterval = 3.5 * 60
    }

    private let context: NSManagedObjectContext

    init(resolver: Resolver, context: NSManagedObjectContext? = nil) {
        self.context = context ?? CoreDataStack.shared.newTaskContext()
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

    func storeGlucose(_ glucose: [BloodGlucose]) async throws {
        try await context.perform {
            // Get new glucose values that don't exist yet
            let newGlucose = self.filterNewGlucoseValues(glucose)
            guard !newGlucose.isEmpty else { return }

            do {
                // Store glucose values in Core Data
                try self.storeGlucoseInCoreData(newGlucose)
            } catch {
                throw CoreDataError.creationError(
                    function: #function,
                    file: #fileID
                )
            }

            // Store CGM state if needed
            self.storeCGMState(glucose)
        }
    }

    private func filterNewGlucoseValues(_ glucose: [BloodGlucose]) -> [BloodGlucose] {
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
            let results = try context.fetch(fetchRequest) as? [NSDictionary]
            existingDates = Set(results?.compactMap({ $0["date"] as? Date }) ?? [])
        } catch {
            debugPrint("Failed to fetch existing glucose dates: \(error)")
        }

        return glucose.filter { !existingDates.contains($0.dateString) }
    }

    private func storeGlucoseInCoreData(_ glucose: [BloodGlucose]) throws {
        if glucose.count > 1 {
            try storeGlucoseBatch(glucose)
        } else {
            try storeGlucoseRegular(glucose)
        }
    }

    private func storeGlucoseRegular(_ glucose: [BloodGlucose]) throws {
        for entry in glucose {
            let glucoseEntry = GlucoseStored(context: context)
            configureGlucoseEntry(glucoseEntry, with: entry)
        }

        guard context.hasChanges else { return }
        try context.save()
    }

    private func storeGlucoseBatch(_ glucose: [BloodGlucose]) throws {
        var remainingGlucose = glucose
        let batchInsert = NSBatchInsertRequest(
            entity: GlucoseStored.entity(),
            managedObjectHandler: { (managedObject: NSManagedObject) -> Bool in
                guard let glucoseEntry = managedObject as? GlucoseStored,
                      !remainingGlucose.isEmpty
                else {
                    return true
                }
                let entry = remainingGlucose.removeFirst()
                self.configureGlucoseEntry(glucoseEntry, with: entry)
                return false
            }
        )
        try context.execute(batchInsert)
        // Only send update for batch insert since regular save triggers CoreData notifications
        updateSubject.send()
    }

    private func configureGlucoseEntry(_ entry: GlucoseStored, with glucose: BloodGlucose) {
        entry.id = UUID()
        entry.glucose = Int16(glucose.glucose ?? 0)
        entry.date = glucose.dateString
        entry.direction = glucose.direction?.rawValue
        entry.isUploadedToNS = false
        entry.isUploadedToHealth = false
        entry.isUploadedToTidepool = false
    }

    private func storeCGMState(_ glucose: [BloodGlucose]) {
        debug(.deviceManager, "start storage cgmState")
        storage.transaction { storage in
            let file = OpenAPS.Monitor.cgmState
            var treatments = storage.retrieve(file, as: [NightscoutTreatment].self) ?? []
            var updated = false

            for x in glucose {
                guard let sessionStartDate = x.sessionStartDate else { continue }

                // Skip if we already have a recent treatment
                if let lastTreatment = treatments.last,
                   let createdAt = lastTreatment.createdAt,
                   abs(createdAt.timeIntervalSince(sessionStartDate)) < TimeInterval(60)
                {
                    continue
                }

                let notes = createCGMStateNotes(transmitterID: x.transmitterID, activationDate: x.activationDate)
                let treatment = createCGMStateTreatment(sessionStartDate: sessionStartDate, notes: notes)

                debug(.deviceManager, "CGM sensor change \(treatment)")
                treatments.append(treatment)
                updated = true
            }

            if updated {
                storage.save(
                    treatments.filter { $0.createdAt?.addingTimeInterval(30.days.timeInterval) ?? .distantPast > Date() },
                    as: file
                )
            }
        }
    }

    private func createCGMStateNotes(transmitterID: String?, activationDate: Date?) -> String {
        var notes = ""
        if let t = transmitterID {
            notes = t
        }
        if let a = activationDate {
            notes = "\(notes) activated on \(a)"
        }
        return notes
    }

    private func createCGMStateTreatment(sessionStartDate: Date, notes: String) -> NightscoutTreatment {
        NightscoutTreatment(
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
    }

    func addManualGlucose(glucose: Int) {
        context.perform {
            let newItem = GlucoseStored(context: self.context)
            newItem.id = UUID()
            newItem.date = Date()
            newItem.glucose = Int16(glucose)
            newItem.isManual = true
            newItem.isUploadedToNS = false
            newItem.isUploadedToHealth = false
            newItem.isUploadedToTidepool = false

            do {
                guard self.context.hasChanges else { return }
                try self.context.save()

                // Glucose subscribers already listen to the update publisher, so call here to update glucose-related data.
                self.updateSubject.send()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save manual glucose to Core Data with error: \(error)"
                )
            }
        }
    }

    func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool {
        guard let glucoseDate = glucoseDate else { return false }
        return glucoseDate > Date().addingTimeInterval(-6 * 60)
    }

    func syncDate() -> Date {
        // Optimize fetch request to only get the date
        let taskContext = CoreDataStack.shared.newTaskContext()
        let fr = NSFetchRequest<NSDictionary>(entityName: "GlucoseStored")
        fr.predicate = NSPredicate.predicateForOneDayAgo
        fr.propertiesToFetch = ["date"]
        fr.fetchLimit = 1
        fr.resultType = .dictionaryResultType
        fr.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        var fetchedDate: Date = .distantPast

        taskContext.performAndWait {
            do {
                if let result = try taskContext.fetch(fr).first,
                   let date = result["date"] as? Date
                {
                    fetchedDate = date
                }
            } catch {
                debugPrint("Fetch error: \(DebuggingIdentifiers.failed) \(error)")
            }
        }

        return fetchedDate
    }

    func lastGlucoseDate() -> Date {
        let fr = GlucoseStored.fetchRequest()
        fr.predicate = NSPredicate.predicateForOneDayAgo
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
        fr.fetchLimit = 1

        var date: Date?
        context.performAndWait {
            do {
                let results = try self.context.fetch(fr)
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

    func fetchLatestGlucose() throws -> GlucoseStored? {
        let predicate = NSPredicate.predicateFor20MinAgo
        return (try CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: 1
        ) as? [GlucoseStored] ?? []).first
    }

    // Fetch glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of BloodGlucose to ensure the correct format for the NS Upload
    func getGlucoseNotYetUploadedToNightscout() async throws -> [BloodGlucose] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucoseNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

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
                    glucose: Int(result.glucose),
                    type: "sgv"
                )
            }
        }
    }

    // Fetch manual glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of NightscoutTreatment to ensure the correct format for the NS Upload
    func getManualGlucoseNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.manualGlucoseNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .capillaryGlucose,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.local,
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
    func getGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucoseNotYetUploadedToHealth,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

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
    func getManualGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.manualGlucoseNotYetUploadedToHealth,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

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
    func getGlucoseNotYetUploadedToTidepool() async throws -> [StoredGlucoseSample] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucoseNotYetUploadedToTidepool,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

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
            .map { $0.convertStoredGlucoseSample(isManualGlucose: false) }
        }
    }

    // Fetch manual glucose that is not uploaded to Tidepool yet
    /// - Returns: Array of StoredGlucoseSample to ensure the correct format for the Tidepool upload
    func getManualGlucoseNotYetUploadedToTidepool() async throws -> [StoredGlucoseSample] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.manualGlucoseNotYetUploadedToTidepool,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

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
            }.map { $0.convertStoredGlucoseSample(isManualGlucose: true) }
        }
    }

    func deleteGlucose(_ treatmentObjectID: NSManagedObjectID) async {
        // Use injected context if available, otherwise create new task context
        let taskContext = context != CoreDataStack.shared.newTaskContext()
            ? context
            : CoreDataStack.shared.newTaskContext()
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
                    "\(#file) \(#function) \(DebuggingIdentifiers.failed) error while deleting glucose from core data: \(error)"
                )
            }
        }
    }

    var alarm: GlucoseAlarm? {
        /// glucose can not be older than 20 minutes due to the predicate in the fetch request
        context.performAndWait {
            do {
                guard let glucose = try fetchLatestGlucose() else { return nil }

                let glucoseValue = glucose.glucose

                if Decimal(glucoseValue) <= settingsManager.settings.lowGlucose {
                    return .low
                }

                if Decimal(glucoseValue) >= settingsManager.settings.highGlucose {
                    return .high
                }

                return nil
            } catch {
                debugPrint("Error fetching latest glucose: \(error)")
                return nil
            }
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
            return String(localized: "LOWALERT!", comment: "LOWALERT!")
        case .low:
            return String(localized: "HIGHALERT!", comment: "HIGHALERT!")
        }
    }
}

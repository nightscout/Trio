import Combine
import CoreData
import Foundation
import SwiftDate
import Swinject

protocol CarbsObserver {
    func carbsDidUpdate(_ carbs: [CarbsEntry])
}

let remoteMealMutationMaximumAge: TimeInterval = 12 * 60 * 60

private struct RemoteMealImportSuppression: Codable {
    let date: Date
    let expiresAt: Date
}

private final class RemoteMealImportSuppressionStore: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private let key = "trio.remoteMealImportSuppressions.v1"
    private let maximumCount = 500

    func record(dates: [Date], now: Date) {
        lock.lock()
        defer { lock.unlock() }

        var suppressions = load().filter { $0.expiresAt >= now }
        for date in dates {
            suppressions.removeAll { abs($0.date.timeIntervalSince(date)) <= 1 }
            suppressions.append(
                RemoteMealImportSuppression(
                    date: date,
                    expiresAt: date.addingTimeInterval(24 * 60 * 60)
                )
            )
        }
        suppressions.sort { $0.expiresAt < $1.expiresAt }
        save(Array(suppressions.suffix(maximumCount)))
    }

    func activeDates(now: Date) -> [Date] {
        lock.lock()
        defer { lock.unlock() }

        let stored = load()
        let active = stored.filter { $0.expiresAt >= now }
        if active.count != stored.count {
            save(active)
        }
        return active.map(\.date)
    }

    private func load() -> [RemoteMealImportSuppression] {
        guard let data = defaults.data(forKey: key),
              let suppressions = try? JSONDecoder().decode([RemoteMealImportSuppression].self, from: data)
        else { return [] }
        return suppressions
    }

    private func save(_ suppressions: [RemoteMealImportSuppression]) {
        guard let data = try? JSONEncoder().encode(suppressions) else { return }
        defaults.set(data, forKey: key)
    }
}

struct MealMutationValues: Codable, Equatable, Sendable {
    let date: Date
    let carbs: Decimal
    let fat: Decimal
    let protein: Decimal
}

struct MealFPUEntrySnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let carbs: Decimal
}

struct MealMutationSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let fpuID: UUID?
    let values: MealMutationValues
    let note: String?
    let fpuEntries: [MealFPUEntrySnapshot]
}

enum MealMutation: Equatable, Sendable {
    case edit(MealMutationValues)
    case delete
}

enum MealMutationDisposition: String, Codable, Equatable, Sendable {
    case unchanged
    case edited
    case deleted
}

struct MealMutationResult: Equatable, Sendable {
    let disposition: MealMutationDisposition
    let before: MealMutationSnapshot
    let after: MealMutationSnapshot?
}

enum MealMutationError: LocalizedError, Equatable {
    case invalidExpectedValues
    case invalidReplacementValues
    case notFound
    case ambiguousIdentifier
    case targetIsFPU
    case invalidStoredEntry
    case outsideEditWindow
    case replacementOutsideEditWindow
    case stale(current: MealMutationValues)

    var errorDescription: String? {
        switch self {
        case .invalidExpectedValues:
            return "The expected meal values are incomplete or invalid."
        case .invalidReplacementValues:
            return "The replacement meal values are incomplete or invalid."
        case .notFound:
            return "The meal entry was not found."
        case .ambiguousIdentifier:
            return "The meal identifier matched more than one entry."
        case .targetIsFPU:
            return "Generated FPU entries cannot be edited directly."
        case .invalidStoredEntry:
            return "The stored meal entry is incomplete or invalid."
        case .outsideEditWindow:
            return "The meal entry is outside the 12-hour edit window."
        case .replacementOutsideEditWindow:
            return "The replacement meal time is outside the 12-hour edit window."
        case .stale:
            return "The meal entry changed after LoopFollow loaded it. Refresh the entry and try again."
        }
    }
}

protocol CarbsStorage {
    var updatePublisher: AnyPublisher<Void, Never> { get }
    func storeCarbs(_ carbs: [CarbsEntry], areFetchedFromRemote: Bool) async throws
    /// Builds a single, real, locally-entered carb entry ready to pass to `storeCarbs`.
    func makeCarbEntry(carbs: Decimal, date: Date) -> CarbsEntry
    func deleteCarbsEntryStored(_ treatmentObjectID: NSManagedObjectID) async
    func syncDate() -> Date
    func getCarbsForAlgorithm(additionalCarbs: Decimal?, carbsDate: Date?) async throws -> [CarbsEntry]
    func getCarbsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getFPUsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getCarbsNotYetUploadedToHealth() async throws -> [CarbsEntry]
    func getCarbsNotYetUploadedToTidepool() async throws -> [CarbsEntry]
    func mealSnapshot(id: UUID, now: Date) async throws -> MealMutationSnapshot
    func mutateMeal(
        id: UUID,
        expected: MealMutationValues,
        mutation: MealMutation,
        now: Date
    ) async throws -> MealMutationResult
    func markMealForUpload(id: UUID) async throws
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private static let remoteImportSuppressions = RemoteMealImportSuppressionStore()

    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    private let updateSubject = PassthroughSubject<Void, Never>()

    private let settingsProvider = PickerSettingsProvider.shared

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    private let makeContext: () -> NSManagedObjectContext
    private let mutationContext: NSManagedObjectContext

    init(resolver: Resolver, contextProvider: (() -> NSManagedObjectContext)? = nil) {
        let makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        self.makeContext = makeContext
        mutationContext = makeContext()
        mutationContext.name = "mutateMeal"
        mutationContext.mergePolicy = NSErrorMergePolicy
        injectServices(resolver)
    }

    func mealSnapshot(id: UUID, now: Date) async throws -> MealMutationSnapshot {
        try await mutationContext.perform {
            self.mutationContext.reset()
            let (root, children) = try self.mutationTarget(id: id, now: now, in: self.mutationContext)
            return try Self.snapshot(root: root, children: children)
        }
    }

    func mutateMeal(
        id: UUID,
        expected: MealMutationValues,
        mutation: MealMutation,
        now: Date
    ) async throws -> MealMutationResult {
        guard Self.hasValidMacros(expected) else {
            throw MealMutationError.invalidExpectedValues
        }

        let result = try await mutationContext.perform {
            self.mutationContext.reset()
            do {
                let (root, children) = try self.mutationTarget(id: id, now: now, in: self.mutationContext)
                let before = try Self.snapshot(root: root, children: children)

                switch mutation {
                case let .edit(replacement):
                    guard Self.hasValidMacros(replacement) else {
                        throw MealMutationError.invalidReplacementValues
                    }

                    let replacementAge = now.timeIntervalSince(replacement.date)
                    guard replacementAge >= 0, replacementAge <= remoteMealMutationMaximumAge else {
                        throw MealMutationError.replacementOutsideEditWindow
                    }

                    if Self.matches(before.values, replacement) {
                        return MealMutationResult(
                            disposition: .unchanged,
                            before: before,
                            after: before
                        )
                    }

                    guard Self.matches(before.values, expected) else {
                        throw MealMutationError.stale(current: before.values)
                    }

                    Self.suppressRemoteImports(for: before, now: now)
                    children.forEach(self.mutationContext.delete)

                    root.date = replacement.date
                    root.carbs = Self.double(replacement.carbs)
                    root.fat = Self.double(replacement.fat)
                    root.protein = Self.double(replacement.protein)
                    // Keep the replacement hidden from automatic upload observers until the
                    // handler has requested deletion of the previous remote representation.
                    root.isUploadedToNS = true
                    root.isUploadedToHealth = true
                    root.isUploadedToTidepool = true

                    var replacementChildren: [CarbEntryStored] = []
                    if replacement.fat > 0 || replacement.protein > 0 {
                        let fpuID = UUID()
                        root.fpuID = fpuID

                        let entry = CarbsEntry(
                            id: id.uuidString,
                            createdAt: now,
                            actualDate: replacement.date,
                            carbs: replacement.carbs,
                            fat: replacement.fat,
                            protein: replacement.protein,
                            note: root.note,
                            enteredBy: CarbsEntry.local,
                            isFPU: false,
                            fpuID: fpuID.uuidString
                        )
                        let (futureEntries, _) = self.processFPU(
                            entries: [entry],
                            fat: replacement.fat,
                            protein: replacement.protein,
                            createdAt: now,
                            actualDate: replacement.date
                        )

                        for futureEntry in futureEntries {
                            guard let childID = futureEntry.id.flatMap(UUID.init(uuidString:)),
                                  let childDate = futureEntry.actualDate
                            else {
                                throw MealMutationError.invalidStoredEntry
                            }

                            let child = CarbEntryStored(context: self.mutationContext)
                            child.id = childID
                            child.fpuID = fpuID
                            child.date = childDate
                            child.carbs = Self.double(futureEntry.carbs)
                            child.fat = 0
                            child.protein = 0
                            child.isFPU = true
                            child.isUploadedToNS = true
                            // FPU carb equivalents are Nightscout-only. Leaving the Health and
                            // Tidepool flags nil matches the existing batch-insert behavior.
                            replacementChildren.append(child)
                        }
                    } else {
                        root.fpuID = nil
                    }

                    try self.mutationContext.save()
                    let after = try Self.snapshot(root: root, children: replacementChildren)
                    return MealMutationResult(disposition: .edited, before: before, after: after)

                case .delete:
                    guard Self.matches(before.values, expected) else {
                        throw MealMutationError.stale(current: before.values)
                    }

                    Self.suppressRemoteImports(for: before, now: now)
                    children.forEach(self.mutationContext.delete)
                    self.mutationContext.delete(root)
                    try self.mutationContext.save()
                    return MealMutationResult(disposition: .deleted, before: before, after: nil)
                }
            } catch {
                self.mutationContext.rollback()
                throw error
            }
        }

        if result.disposition != .unchanged {
            updateSubject.send(())
        }
        return result
    }

    func markMealForUpload(id: UUID) async throws {
        try await mutationContext.perform {
            self.mutationContext.reset()
            do {
                let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@ AND isFPU == NO", id as CVarArg)
                request.fetchLimit = 2

                let matches = try self.mutationContext.fetch(request)
                guard matches.isNotEmpty else {
                    throw MealMutationError.notFound
                }
                guard matches.count == 1 else {
                    throw MealMutationError.ambiguousIdentifier
                }
                let root = matches[0]

                root.isUploadedToNS = false
                root.isUploadedToHealth = false
                root.isUploadedToTidepool = false
                for child in try self.fpuEntries(for: root.fpuID, in: self.mutationContext) {
                    child.isUploadedToNS = false
                }

                if self.mutationContext.hasChanges {
                    try self.mutationContext.save()
                }
            } catch {
                self.mutationContext.rollback()
                throw error
            }
        }
    }

    private func mutationTarget(
        id: UUID,
        now: Date,
        in context: NSManagedObjectContext
    ) throws -> (root: CarbEntryStored, children: [CarbEntryStored]) {
        let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 2

        let matches = try context.fetch(request)
        guard matches.isNotEmpty else {
            throw MealMutationError.notFound
        }
        guard matches.count == 1 else {
            throw MealMutationError.ambiguousIdentifier
        }

        let root = matches[0]
        guard !root.isFPU else {
            throw MealMutationError.targetIsFPU
        }
        guard root.id == id, let rootDate = root.date else {
            throw MealMutationError.invalidStoredEntry
        }

        let age = now.timeIntervalSince(rootDate)
        guard age >= 0, age <= remoteMealMutationMaximumAge else {
            throw MealMutationError.outsideEditWindow
        }

        return (root, try fpuEntries(for: root.fpuID, in: context))
    }

    private func fpuEntries(
        for fpuID: UUID?,
        in context: NSManagedObjectContext
    ) throws -> [CarbEntryStored] {
        guard let fpuID else { return [] }

        let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "fpuID == %@", fpuID as CVarArg),
            NSPredicate(format: "isFPU == YES")
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return try context.fetch(request)
    }

    private static func snapshot(
        root: CarbEntryStored,
        children: [CarbEntryStored]
    ) throws -> MealMutationSnapshot {
        guard let id = root.id, let date = root.date else {
            throw MealMutationError.invalidStoredEntry
        }

        let childSnapshots = try children.map { child in
            guard let childID = child.id, let childDate = child.date else {
                throw MealMutationError.invalidStoredEntry
            }
            return MealFPUEntrySnapshot(
                id: childID,
                date: childDate,
                carbs: Decimal(algorithmValue: child.carbs)
            )
        }

        return MealMutationSnapshot(
            id: id,
            fpuID: root.fpuID,
            values: MealMutationValues(
                date: date,
                carbs: Decimal(algorithmValue: root.carbs),
                fat: Decimal(algorithmValue: root.fat),
                protein: Decimal(algorithmValue: root.protein)
            ),
            note: root.note,
            fpuEntries: childSnapshots
        )
    }

    private static func hasValidMacros(_ values: MealMutationValues) -> Bool {
        let macros = [values.carbs, values.fat, values.protein]
        return values.date.timeIntervalSinceReferenceDate.isFinite &&
            macros.allSatisfy { $0 >= 0 && NSDecimalNumber(decimal: $0).doubleValue.isFinite } &&
            macros.contains(where: { $0 > 0 })
    }

    private static func suppressRemoteImports(for snapshot: MealMutationSnapshot, now: Date) {
        remoteImportSuppressions.record(
            dates: [snapshot.values.date] + snapshot.fpuEntries.map(\.date),
            now: now
        )
    }

    private static func matches(_ lhs: MealMutationValues, _ rhs: MealMutationValues) -> Bool {
        lhs.carbs == rhs.carbs &&
            lhs.fat == rhs.fat &&
            lhs.protein == rhs.protein &&
            abs(lhs.date.timeIntervalSince(rhs.date)) <= 1
    }

    private static func double(_ value: Decimal) -> Double {
        Double(truncating: NSDecimalNumber(decimal: value))
    }

    func storeCarbs(_ entries: [CarbsEntry], areFetchedFromRemote: Bool) async throws {
        var entriesToStore = entries

        if areFetchedFromRemote {
            entriesToStore = try await filterRemoteEntries(entries: entriesToStore)
        }

        // Check for FPU-only entries (fat/protein without carbs)
        let fpuOnlyEntries = entriesToStore.filter { entry in
            entry.carbs == 0 && (entry.fat ?? 0 > 0 || entry.protein ?? 0 > 0)
        }

        // Create additional Carb (non-FPU) entries with fat/protein amounts and carbs == 0
        for entry in fpuOnlyEntries {
            let additionalEntry = CarbsEntry(
                id: entry.id,
                createdAt: entry.createdAt,
                actualDate: entry.actualDate,
                carbs: Decimal(0),
                fat: entry.fat,
                protein: entry.protein,
                note: entry.note,
                enteredBy: entry.enteredBy,
                isFPU: false, // it should be a Carb entry
                fpuID: entry.fpuID
            )
            entriesToStore.append(additionalEntry)
        }

        await saveCarbsToCoreData(entries: entriesToStore, areFetchedFromRemote: areFetchedFromRemote)
        await saveCarbEquivalents(entries: entriesToStore, areFetchedFromRemote: areFetchedFromRemote)
    }

    private func filterRemoteEntries(entries: [CarbsEntry]) async throws -> [CarbsEntry] {
        let context = makeContext()
        context.name = "filterRemoteEntries"
        // Fetch only the date property from Core Data
        guard let existing24hCarbEntries = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false,
            batchSize: 50,
            propertiesToFetch: ["date", "objectID"]
        ) as? [[String: Any]] else {
            return entries
        }

        // Extract dates into a set for efficient lookup
        // Since we are not dealing with NSManagedObjects directly it is safe to pass properties between threads
        let existingTimestamps = Set(existing24hCarbEntries.compactMap { $0["date"] as? Date })
        let suppressedTimestamps = Self.remoteImportSuppressions.activeDates(now: Date())

        // A remote mutation can remove the old local timestamp before Nightscout has
        // processed its deletion. Keep that stale treatment from being re-imported.
        var filteredEntries = entries
        filteredEntries.removeAll { entry in
            let entryDate = entry.actualDate ?? entry.createdAt
            return existingTimestamps.contains(entryDate) ||
                suppressedTimestamps.contains { abs($0.timeIntervalSince(entryDate)) <= 1 }
        }

        return filteredEntries
    }

    /**
     Converts fat and protein into delayed carb-equivalent entries (FPU handling).

     Behavior:

     - Calculates carb equivalents from fat and protein
       ((fat × 9 + protein × 4) / 10 × adjustment factor).
     - Rounds down to whole grams.
     - Drops values below 10 g.
     - Caps total equivalents at 99 g.
     - Splits into up to 3 entries.
     - Caps each entry at 33 g.
     - Distributes grams as evenly as possible.

     Timing:

     - First entry is scheduled after the configured delay
       (default: 60 minutes) from the carb entry timestamp.
     - Additional entries are spaced 30 minutes apart.

     Example (default):

     - Carb entry at T
     - 1st equivalent at T + 60 min
     - 2nd equivalent at T + 90 min
     - 3rd equivalent at T + 120 min

     Generated entries:

     - Are marked with `isFPU = true`
     - Contain only carbs (fat and protein set to 0)
     - Share the same `fpuID` as the original carb entry

     - Parameters:
       - entries: An array of `CarbsEntry` objects representing the carb equivalent entries to be processed.
       - fat: The amount of fat in the last entry.
       - protein: The amount of protein in the last entry.
       - createdAt: The creation date of the last entry.

     - Returns: A tuple containing the array of future carb entries and the total carb equivalents.
     */
    private func processFPU(
        entries: [CarbsEntry],
        fat: Decimal,
        protein: Decimal,
        createdAt: Date,
        actualDate: Date?
    ) -> ([CarbsEntry], Decimal) {
        let trioSettings = settings.settings
        let providerSettings = settingsProvider.settings

        let adjustment = trioSettings.individualAdjustmentFactor
            .clamp(to: providerSettings.individualAdjustmentFactor)

        let delayMinutes = trioSettings.delay
            .clamp(to: providerSettings.delay)

        let spreadInterval = trioSettings.minuteInterval
            .clamp(to: providerSettings.minuteInterval)

        // Constraints
        let maxTotalGrams = 99
        let maxEntries = 3
        let maxPerEntry = 33
        let minPerEntry = 10
        let spacing = TimeInterval(spreadInterval * 60)

        // kcal -> carb equivalents (kcal/10 * adjustment), rounded down to whole grams
        let kcal = protein * 4 + fat * 9
        let rawEquivalents = Int((kcal / 10) * adjustment)
        let totalGrams = min(maxTotalGrams, max(0, rawEquivalents))

        guard totalGrams >= minPerEntry else {
            return ([], Decimal(totalGrams))
        }

        let amounts = splitIntoCarbEquivalents(
            total: totalGrams,
            maxEntries: maxEntries,
            maxPerEntry: maxPerEntry,
            minPerEntry: minPerEntry
        )

        let baseDate = actualDate ?? createdAt
        let start = baseDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
        let fpuID = entries.first?.fpuID ?? UUID().uuidString

        let futureEntries: [CarbsEntry] = amounts.enumerated().map { idx, grams in
            CarbsEntry(
                id: UUID().uuidString,
                createdAt: createdAt,
                actualDate: start.addingTimeInterval(TimeInterval(idx) * spacing),
                carbs: Decimal(grams),
                fat: 0,
                protein: 0,
                note: nil,
                enteredBy: CarbsEntry.local,
                isFPU: true,
                fpuID: fpuID
            )
        }

        let totalScheduled = futureEntries.reduce(into: Decimal(0)) { $0 += $1.carbs }
        return (futureEntries, totalScheduled)
    }

    /**
     Splits a total carb-equivalent value into multiple integer entries.

     - Returns no entries if `total` is below `minPerEntry`.
     - Limits output to `maxEntries`.
     - Caps each entry at `maxPerEntry`.
     - Distributes grams evenly (difference ≤ 1 g).
     - Merges or removes entries below `minPerEntry`.

     - Returns:
       Integer gram values representing the split carb equivalents.
     */
    private func splitIntoCarbEquivalents(
        total: Int,
        maxEntries: Int,
        maxPerEntry: Int,
        minPerEntry: Int
    ) -> [Int] {
        guard total >= minPerEntry else { return [] }

        // Choose an entry count that *guarantees* each entry can be <= maxPerEntry
        let needed = (total + maxPerEntry - 1) / maxPerEntry
        let count = min(maxEntries, max(1, needed))

        // Even split (difference between buckets is at most 1)
        func evenSplit(_ total: Int, count: Int) -> [Int] {
            let base = total / count
            let rem = total % count
            return (0 ..< count).map { base + ($0 < rem ? 1 : 0) }
        }

        var buckets = evenSplit(total, count: count)

        // Enforce minPerEntry by merging any too-small tail bucket into the previous one
        // This should be rare, but it keeps the invariant
        if buckets.count > 1 {
            for i in stride(from: buckets.count - 1, through: 1, by: -1) {
                let v = buckets[i]
                guard v > 0, v < minPerEntry else { continue }
                buckets[i - 1] += v
                buckets[i] = 0
            }
            buckets = buckets.filter { $0 > 0 }
        }

        // Guarantee not to exceed maxPerEntry if merging a reduced count
        // Clamp as final guard here
        buckets = buckets.map { min(maxPerEntry, $0) }.filter { $0 >= minPerEntry }

        return buckets
    }

    private func saveCarbEquivalents(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        guard let lastEntry = entries.last else { return }

        if let fat = lastEntry.fat, let protein = lastEntry.protein, fat > 0 || protein > 0 {
            let (futureCarbEquivalents, carbEquivalentCount) = processFPU(
                entries: entries,
                fat: fat,
                protein: protein,
                createdAt: lastEntry.createdAt,
                actualDate: lastEntry.actualDate
            )

            if carbEquivalentCount > 0 {
                await saveFPUToCoreDataAsBatchInsert(entries: futureCarbEquivalents, areFetchedFromRemote: areFetchedFromRemote)
            }
        }
    }

    private func saveCarbsToCoreData(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        guard let entry = entries.last else { return }

        let context = makeContext()
        context.name = "saveCarbsToCoreData"
        await context.perform {
            let newItem = CarbEntryStored(context: context)
            newItem.date = entry.actualDate ?? entry.createdAt
            newItem.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            newItem.fat = Double(truncating: NSDecimalNumber(decimal: entry.fat ?? 0))
            newItem.protein = Double(truncating: NSDecimalNumber(decimal: entry.protein ?? 0))
            newItem.note = entry.note
            newItem.id = UUID()
            newItem.isFPU = false
            newItem.isUploadedToNS = areFetchedFromRemote ? true : false
            newItem.isUploadedToHealth = false
            newItem.isUploadedToTidepool = false

            if entry.fat != nil, entry.protein != nil, let fpuId = entry.fpuID {
                newItem.fpuID = UUID(uuidString: fpuId)
            }

            do {
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    private func saveFPUToCoreDataAsBatchInsert(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        let commonFPUID = UUID(
            uuidString: entries.first?.fpuID ?? UUID()
                .uuidString
        ) // all fpus should only get ONE id per batch insert to be able to delete them referencing the fpuID
        var entrySlice = ArraySlice(entries) // convert to ArraySlice
        let batchInsert = NSBatchInsertRequest(entity: CarbEntryStored.entity()) { (managedObject: NSManagedObject) -> Bool in
            guard let carbEntry = managedObject as? CarbEntryStored, let entry = entrySlice.popFirst(),
                  let entryId = entry.id
            else {
                return true // return true to stop
            }
            carbEntry.date = entry.actualDate
            carbEntry.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            carbEntry.id = UUID.init(uuidString: entryId)
            carbEntry.fpuID = commonFPUID
            carbEntry.isFPU = true
            carbEntry.isUploadedToNS = areFetchedFromRemote ? true : false
            // do NOT set Health and Tidepool flags to ensure they will NOT be uploaded
            return false // return false to continue
        }
        let context = makeContext()
        context.name = "saveFPUToCoreDataAsBatchInsert"
        await context.perform {
            do {
                try context.execute(batchInsert)
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.succeeded) saved fpus to core data")

                // Notify subscriber in Home State Model to update the FPU Array
                self.updateSubject.send(())
            } catch {
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.failed) error while saving fpus to core data")
            }
        }
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    /// Fetches the last day of carbs and converts them into the `CarbsEntry` values the oref algorithm
    /// consumes, optionally appending a synthetic "additional carbs" entry for bolus simulation.
    func getCarbsForAlgorithm(additionalCarbs: Decimal? = nil, carbsDate: Date? = nil) async throws -> [CarbsEntry] {
        let context = makeContext()
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let carbResults = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            var entries = carbResults.map { Self.mapToCarbsEntry($0) }

            if let additionalCarbs = additionalCarbs {
                entries.append(Self.additionalCarbsEntry(carbs: additionalCarbs, date: carbsDate ?? Date()))
            }

            return entries
        }
    }

    /// Converts CoreData stored carb entries into a struct that the oref algorithm can use
    static func mapToCarbsEntry(_ carbEntry: CarbEntryStored) -> CarbsEntry {
        // The old encode used `date ?? Date()` for both created_at and actualDate.
        let date = carbEntry.date ?? Date()
        return CarbsEntry(
            id: carbEntry.id?.uuidString,
            createdAt: date,
            actualDate: date,
            carbs: Decimal(algorithmValue: carbEntry.carbs),
            fat: Decimal(algorithmValue: carbEntry.fat),
            protein: Decimal(algorithmValue: carbEntry.protein),
            note: nil,
            enteredBy: CarbsEntry.local,
            isFPU: carbEntry.isFPU,
            fpuID: nil
        )
    }

    /// Builds the synthetic "additional carbs" entry that the determine-basal flow appends for bolus
    /// simulation.
    static func additionalCarbsEntry(carbs: Decimal, date: Date, id: String = UUID().uuidString) -> CarbsEntry {
        CarbsEntry(
            id: id,
            createdAt: date,
            actualDate: date,
            carbs: carbs,
            fat: 0,
            protein: 0,
            note: nil,
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: nil
        )
    }

    /// Builds a single, real, locally-entered carb entry ready to pass to `storeCarbs`. Kept separate from
    /// `additionalCarbsEntry`, which is for the determine-basal flow's synthetic bolus-simulation input.
    func makeCarbEntry(carbs: Decimal, date: Date) -> CarbsEntry {
        CarbsEntry(
            id: UUID().uuidString,
            createdAt: date,
            actualDate: date,
            carbs: carbs,
            fat: 0,
            protein: 0,
            note: nil,
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: nil
        )
    }

    func deleteCarbsEntryStored(_ treatmentObjectID: NSManagedObjectID) async {
        let context = makeContext()
        context.name = "deleteCarbsEntryStored"

        var carbEntryFromCoreData: CarbEntryStored?

        await context.perform {
            do {
                carbEntryFromCoreData = try context.existingObject(with: treatmentObjectID) as? CarbEntryStored
                guard let carbEntry = carbEntryFromCoreData else {
                    debugPrint("Carb entry for batch delete not found. \(DebuggingIdentifiers.failed)")
                    return
                }

                // entry has fpuID
                // case 1: carb equivalent entry
                // case 2: "parent" entry, but containing fat and/or protein, and possibly carbs
                // => use fpuID ID to delete all corresponding entries via batch delete
                if let fpuID = carbEntry.fpuID {
                    // fetch request for all carb entries with the same id
                    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CarbEntryStored.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "fpuID == %@", fpuID as CVarArg)

                    // NSBatchDeleteRequest
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                    deleteRequest.resultType = .resultTypeCount

                    // execute the batch delete request
                    let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                    debugPrint("\(DebuggingIdentifiers.succeeded) Deleted \(result?.result ?? 0) items with FpuID \(fpuID)")

                    // Notifiy subscribers of the batch delete
                    self.updateSubject.send(())
                }
                // entry has no fpuID
                // => it's a carb-only entry. use its ID to for deletion
                else {
                    context.delete(carbEntry)

                    guard context.hasChanges else { return }
                    try context.save()

                    debugPrint(
                        "CarbsStorage: \(#function) \(DebuggingIdentifiers.succeeded) deleted carb entry from core data"
                    )
                }

            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error deleting carb entry: \(error)")
            }
        }
    }

    func getCarbsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let context = makeContext()
        context.name = "getCarbsNotYetUploadedToNightscout"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            // Include fat/protein-only roots so Nightscout (and therefore LoopFollow) exposes
            // the stable Trio meal UUID needed for a later edit or deletion.
            predicate: NSPredicate(
                format: "date >= %@ AND isUploadedToNS == %@ AND isFPU == %@ AND " +
                    "(carbs > 0 OR fat > 0 OR protein > 0)",
                Date.oneDayAgo as NSDate,
                false as NSNumber,
                false as NSNumber
            ),
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let carbEntries = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return carbEntries.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.local,
                    bolus: nil,
                    insulin: nil,
                    notes: result.note,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    foodType: result.note,
                    targetTop: nil,
                    targetBottom: nil,
                    id: result.id?.uuidString
                )
            }
        }
    }

    func getFPUsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let context = makeContext()
        context.name = "getFPUsNotYetUploadedToNightscout"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.fpusNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fpuEntries = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fpuEntries.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.local,
                    bolus: nil,
                    insulin: nil,
                    notes: result.note,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    foodType: result.note,
                    targetTop: nil,
                    targetBottom: nil,
                    id: result.fpuID?.uuidString
                )
            }
        }
    }

    func getCarbsNotYetUploadedToHealth() async throws -> [CarbsEntry] {
        let context = makeContext()
        context.name = "getCarbsNotYetUploadedToHealth"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.carbsNotYetUploadedToHealth,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let carbEntries = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return carbEntries.map { result in
                CarbsEntry(
                    id: result.id?.uuidString,
                    createdAt: result.date ?? Date(),
                    actualDate: result.date,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    note: result.note,
                    enteredBy: CarbsEntry.local,
                    isFPU: result.isFPU,
                    fpuID: result.fpuID?.uuidString
                )
            }
        }
    }

    func getCarbsNotYetUploadedToTidepool() async throws -> [CarbsEntry] {
        let context = makeContext()
        context.name = "getCarbsNotYetUploadedToTidepool"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.carbsNotYetUploadedToTidepool,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let carbEntries = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return carbEntries.map { result in
                CarbsEntry(
                    id: result.id?.uuidString,
                    createdAt: result.date ?? Date(),
                    actualDate: result.date,
                    carbs: Decimal(result.carbs),
                    fat: nil,
                    protein: nil,
                    note: result.note,
                    enteredBy: CarbsEntry.local,
                    isFPU: nil,
                    fpuID: nil
                )
            }
        }
    }
}

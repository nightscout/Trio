import CoreData
import Foundation
import HealthKit
import Swinject

/// Values of a meal root row, safe to pass between threads.
struct MealSnapshot: Equatable, Sendable {
    let id: UUID
    let fpuID: UUID?
    let date: Date
    let carbs: Decimal
    let fat: Decimal
    let protein: Decimal
    let note: String?
}

enum CarbEntryMutationError: Error, Equatable {
    case rootNotFound
    case notARoot
    case invalidReplacementID
}

/// Deletes and replaces a meal family (root plus FPU carb equivalents) in Core Data, Nightscout, Apple Health and Tidepool.
/// Core Data changes run one mutation at a time and finish before any remote call, so COB never waits on the network.
/// Remote deletes and uploads are awaited before returning. Callers run `determineBasalSync()` afterwards.
/// Returned failure messages are Nightscout delete failures; the list is empty when Nightscout succeeded or is not configured.
protocol CarbEntryMutationService {
    func deleteMeal(rootObjectID: NSManagedObjectID) async throws -> [String]
    /// Returns the new root id, which is `replacement.id`.
    func replaceMeal(rootObjectID: NSManagedObjectID, with replacement: CarbsEntry) async throws
        -> (newID: UUID, failures: [String])
}

final class BaseCarbEntryMutationService: CarbEntryMutationService, Injectable {
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var nightscoutManager: NightscoutManager!
    @Injected() private var healthkitManager: HealthKitManager!
    @Injected() private var tidepoolManager: TidepoolManager!

    private let makeContext: () -> NSManagedObjectContext
    private let localMutations = MealMutationQueue()

    init(resolver: Resolver, contextProvider: (() -> NSManagedObjectContext)? = nil) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        injectServices(resolver)
    }

    func deleteMeal(rootObjectID: NSManagedObjectID) async throws -> [String] {
        let snapshot = try await localMutations.run {
            let snapshot = try await self.snapshotRoot(rootObjectID)
            await self.carbsStorage.deleteCarbsEntryStored(rootObjectID)
            return snapshot
        }
        return await deleteFromServices(snapshot)
    }

    func replaceMeal(rootObjectID: NSManagedObjectID, with replacement: CarbsEntry) async throws
        -> (newID: UUID, failures: [String])
    {
        guard let idString = replacement.id, let newID = UUID(uuidString: idString) else {
            throw CarbEntryMutationError.invalidReplacementID
        }
        let snapshot = try await localMutations.run {
            let snapshot = try await self.snapshotRoot(rootObjectID)
            await self.carbsStorage.deleteCarbsEntryStored(rootObjectID)
            try await self.carbsStorage.storeCarbs([replacement], areFetchedFromRemote: false)
            return snapshot
        }
        let failures = await deleteFromServices(snapshot)
        await syncMealsWithServices()
        return (newID, failures)
    }

    private func syncMealsWithServices() async {
        async let nightscoutUpload: () = nightscoutManager.uploadCarbs()
        async let healthKitUpload: () = healthkitManager.uploadCarbs()
        async let tidepoolUpload: () = tidepoolManager.uploadCarbs()
        _ = await [nightscoutUpload, healthKitUpload, tidepoolUpload]
    }

    private func snapshotRoot(_ objectID: NSManagedObjectID) async throws -> MealSnapshot {
        let context = makeContext()
        context.name = "snapshotMealRoot"
        // A fetch reads the store, so rows removed by a batch delete are not served from the row cache.
        let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
        request.predicate = NSPredicate(format: "SELF == %@", objectID)
        request.fetchLimit = 1
        return try await context.perform {
            guard let row = try? context.fetch(request).first,
                  let id = row.id, let date = row.date
            else {
                throw CarbEntryMutationError.rootNotFound
            }
            guard !row.isFPU else {
                throw CarbEntryMutationError.notARoot
            }
            return MealSnapshot(
                id: id,
                fpuID: row.fpuID,
                date: date,
                carbs: Decimal(row.carbs),
                fat: Decimal(row.fat),
                protein: Decimal(row.protein),
                note: row.note
            )
        }
    }

    private func deleteFromServices(_ snapshot: MealSnapshot) async -> [String] {
        var failures: [String] = []

        if let fpuID = snapshot.fpuID {
            if await !nightscoutManager.deleteCarbs(withID: fpuID.uuidString) {
                failures.append("Nightscout: carb equivalents not deleted")
            }
            for sampleType in [AppleHealthConfig.healthFatObject, AppleHealthConfig.healthProteinObject].compactMap({ $0 }) {
                await healthkitManager.deleteMealData(byID: fpuID.uuidString, sampleType: sampleType)
            }
        }

        if await !nightscoutManager.deleteCarbs(withID: snapshot.id.uuidString) {
            failures.append("Nightscout: meal not deleted")
        }
        if let sampleType = AppleHealthConfig.healthCarbObject {
            await healthkitManager.deleteMealData(byID: snapshot.id.uuidString, sampleType: sampleType)
        }
        tidepoolManager.deleteCarbs(
            withSyncId: snapshot.id,
            carbs: snapshot.carbs,
            at: snapshot.date,
            enteredBy: CarbsEntry.local
        )

        return failures
    }
}

/// Runs operations one at a time in submission order, including across suspension points.
private actor MealMutationQueue {
    private var tail: Task<Void, Never>?

    func run<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

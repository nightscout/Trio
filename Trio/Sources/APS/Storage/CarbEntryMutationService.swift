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

/// Per-service failures collected while syncing a meal change. Empty when every service succeeded or was not configured.
struct MealSyncReport: Sendable {
    var failures: [String] = []
}

enum CarbEntryMutationError: Error, Equatable {
    case rootNotFound
    case notARoot
    case invalidReplacementID
}

/// Deletes and replaces a meal family (root plus FPU carb equivalents) in Core Data, Nightscout, Apple Health and Tidepool.
/// Remote deletes are awaited before the local rows go away. Callers run `determineBasalSync()` afterwards.
protocol CarbEntryMutationService {
    func deleteMeal(rootObjectID: NSManagedObjectID) async throws -> MealSyncReport
    /// Returns the new root id, which is `replacement.id`.
    func replaceMeal(rootObjectID: NSManagedObjectID, with replacement: CarbsEntry) async throws
        -> (newID: UUID, report: MealSyncReport)
    func syncMealsWithServices() async
}

final class BaseCarbEntryMutationService: CarbEntryMutationService, Injectable {
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var nightscoutManager: NightscoutManager!
    @Injected() private var healthkitManager: HealthKitManager!
    @Injected() private var tidepoolManager: TidepoolManager!

    private let makeContext: () -> NSManagedObjectContext

    init(resolver: Resolver, contextProvider: (() -> NSManagedObjectContext)? = nil) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        injectServices(resolver)
    }

    func deleteMeal(rootObjectID: NSManagedObjectID) async throws -> MealSyncReport {
        let snapshot = try await snapshotRoot(rootObjectID)
        let report = await deleteFromServices(snapshot)
        await carbsStorage.deleteCarbsEntryStored(rootObjectID)
        return report
    }

    func replaceMeal(rootObjectID: NSManagedObjectID, with replacement: CarbsEntry) async throws
        -> (newID: UUID, report: MealSyncReport)
    {
        guard let idString = replacement.id, let newID = UUID(uuidString: idString) else {
            throw CarbEntryMutationError.invalidReplacementID
        }
        let report = try await deleteMeal(rootObjectID: rootObjectID)
        try await carbsStorage.storeCarbs([replacement], areFetchedFromRemote: false)
        await syncMealsWithServices()
        return (newID, report)
    }

    func syncMealsWithServices() async {
        async let nightscoutUpload: () = nightscoutManager.uploadCarbs()
        async let healthKitUpload: () = healthkitManager.uploadCarbs()
        async let tidepoolUpload: () = tidepoolManager.uploadCarbs()
        _ = await [nightscoutUpload, healthKitUpload, tidepoolUpload]
    }

    private func snapshotRoot(_ objectID: NSManagedObjectID) async throws -> MealSnapshot {
        let context = makeContext()
        context.name = "snapshotMealRoot"
        return try await context.perform {
            guard let row = try? context.existingObject(with: objectID) as? CarbEntryStored,
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

    private func deleteFromServices(_ snapshot: MealSnapshot) async -> MealSyncReport {
        var report = MealSyncReport()

        if let fpuID = snapshot.fpuID {
            if await !nightscoutManager.deleteCarbs(withID: fpuID.uuidString) {
                report.failures.append("Nightscout: carb equivalents not deleted")
            }
            for sampleType in [AppleHealthConfig.healthFatObject, AppleHealthConfig.healthProteinObject].compactMap({ $0 }) {
                await healthkitManager.deleteMealData(byID: fpuID.uuidString, sampleType: sampleType)
            }
        }

        if await !nightscoutManager.deleteCarbs(withID: snapshot.id.uuidString) {
            report.failures.append("Nightscout: meal not deleted")
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

        return report
    }
}

import CoreData
import Foundation
import Swinject

/// Pump, Core Data and preset side effects of watch commands, kept behind a protocol so the
/// processor's validation and sequencing can be tested without a pump.
protocol WatchCommandActions {
    /// Throws unless the carb row was actually saved. `authorize` runs inside the save transaction
    /// before the row is inserted; whatever it throws is rethrown with nothing written.
    func storeCarbs(_ grams: Int, date: Date, authorize: @escaping () throws -> Void) async throws
    /// Returns once the pump accepted or refused the bolus, without waiting for the follow-up loop run.
    /// Throws only what `authorize` threw, run right before issuance; nothing reached the pump then.
    func enactBolus(_ units: Decimal, authorize: @escaping () throws -> Void) async throws -> Bool
    func overridePresets() async throws -> [WatchPresetEntry]
    func tempTargetPresets() async throws -> [WatchPresetEntry]
}

final class BaseWatchCommandActions: WatchCommandActions, Injectable {
    @Injected() private var apsManager: APSManager!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var overrideStorage: OverrideStorage!
    @Injected() private var tempTargetStorage: TempTargetsStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ grams: Int, date: Date, authorize: @escaping () throws -> Void) async throws {
        let entry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: date,
            actualDate: date,
            carbs: Decimal(grams),
            fat: 0,
            protein: 0,
            note: String(localized: "Via Watch", comment: "Note added to carb entry when entered via watch"),
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: nil
        )
        try await carbsStorage.storeVerifiedCarbs(entry, authorize: authorize)
    }

    /// `authorize` runs in the task that issues the request, immediately before `APSManager.enactBolus`
    /// and with nothing awaited in between, so a revocation or expiry cannot land between the final
    /// check and issuance. The task lets the ack return before the determination `enactBolus` runs
    /// after a manual bolus.
    func enactBolus(_ units: Decimal, authorize: @escaping () throws -> Void) async throws -> Bool {
        // enactBolus returns without calling back for non-positive amounts, which would never resume
        guard units > 0, let apsManager = self.apsManager else { return false }
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    try authorize()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                await apsManager.enactBolus(amount: Double(truncating: units as NSNumber), isSMB: false) { success, _ in
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func overridePresets() async throws -> [WatchPresetEntry] {
        let ids = try await overrideStorage.fetchForOverridePresets()
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "watchCommandOverridePresets"
        let rows: [OverrideStored] = try await CoreDataStack.shared.getNSManagedObject(with: ids, context: context)

        return await context.perform {
            rows.compactMap { row in
                guard let name = row.name, let id = row.id else { return nil }
                return WatchPresetEntry(name: name, isActive: row.enabled, ref: .presetID(id))
            }
        }
    }

    func tempTargetPresets() async throws -> [WatchPresetEntry] {
        let ids = try await tempTargetStorage.fetchForTempTargetPresets()
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "watchCommandTempTargetPresets"
        let rows: [TempTargetStored] = try await CoreDataStack.shared.getNSManagedObject(with: ids, context: context)

        return await context.perform {
            rows.compactMap { row in
                guard let name = row.name, let id = row.id else { return nil }
                return WatchPresetEntry(name: name, isActive: row.enabled, ref: .presetID(id.uuidString))
            }
        }
    }
}

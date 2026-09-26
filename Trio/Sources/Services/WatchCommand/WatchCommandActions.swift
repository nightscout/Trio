import CoreData
import Foundation
import Swinject

/// Pump, Core Data and preset side effects of watch commands, kept behind a protocol so the
/// processor's validation and sequencing can be tested without a pump.
protocol WatchCommandActions {
    /// Throws unless the carb row was actually saved.
    func storeCarbs(_ grams: Int, date: Date) async throws
    /// Returns once the pump accepted or refused the bolus, without waiting for the follow-up loop run.
    func enactBolus(_ units: Decimal) async -> Bool
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

    func storeCarbs(_ grams: Int, date: Date) async throws {
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
        try await carbsStorage.storeVerifiedCarbs(entry)
    }

    func enactBolus(_ units: Decimal) async -> Bool {
        // enactBolus returns without calling back for non-positive amounts, which would never resume
        guard units > 0 else { return false }
        let apsManager = self.apsManager
        return await withCheckedContinuation { continuation in
            Task {
                await apsManager?.enactBolus(amount: Double(truncating: units as NSNumber), isSMB: false) { success, _ in
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

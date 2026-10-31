import CoreData
import Foundation
import LoopKit
import Swinject

protocol PumpStatusStorage {
    /// Stores the status when its delivery state differs from the last stored status.
    func storePumpStatus(_ status: PumpManagerStatus)
    /// Stores an unknown delivery state for a removed pump.
    func storePumpRemoved()
    func lastPumpStatus() async -> PumpStatus?
    /// Deletes statuses older than the given number of days, keeping the latest one.
    func deleteStatuses(olderThan days: Int) async
}

final class BasePumpStatusStorage: PumpStatusStorage, Injectable {
    @Injected() private var fileStorage: FileStorage!

    /// One context for all stores, so each compares against the status stored before it, in the order the updates arrive.
    private let context: NSManagedObjectContext

    private static let legacyStatusFile = "monitor/status.json"

    init(resolver: Resolver, contextProvider: (() -> NSManagedObjectContext)? = nil) {
        context = contextProvider?() ?? CoreDataStack.shared.newTaskContext()
        context.name = "pumpStatusStorage"
        injectServices(resolver)
        migrateLegacyStatusFile()
    }

    func storePumpStatus(_ status: PumpManagerStatus) {
        store(PumpStatusStored.DeliveryState(status.basalDeliveryState))
    }

    func storePumpRemoved() {
        store(.unknown)
    }

    func lastPumpStatus() async -> PumpStatus? {
        await context.perform { [context] in
            do {
                return try context.fetch(PumpStatusStored.fetchLast()).first?.pumpStatus
            } catch {
                warning(.storage, "Last pump status fetch failed", error: error)
                return nil
            }
        }
    }

    func deleteStatuses(olderThan days: Int) async {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }

        await context.perform { [context] in
            do {
                guard let latestDate = try context.fetch(PumpStatusStored.fetchLast()).first?.date else { return }
                let request = PumpStatusStored.fetchRequest()
                request.predicate = NSPredicate(format: "date < %@ AND date < %@", cutoff as NSDate, latestDate as NSDate)
                for stored in try context.fetch(request) {
                    context.delete(stored)
                }
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                context.rollback()
                warning(.storage, "Deleting old pump statuses failed", error: error)
            }
        }
    }

    private func store(_ deliveryState: PumpStatusStored.DeliveryState) {
        let date = Date()

        context.perform { [context] in
            do {
                if let last = try context.fetch(PumpStatusStored.fetchLast()).first, last.deliveryState == deliveryState {
                    return
                }

                let stored = PumpStatusStored(context: context)
                stored.date = date
                stored.basalDeliveryState = deliveryState.rawValue
                try context.save()
                debug(.storage, "Pump status stored: \(deliveryState.rawValue)")
            } catch {
                context.rollback()
                warning(.storage, "Saving pump status failed", error: error)
            }
        }
    }

    private func migrateLegacyStatusFile() { // FIXME: this can be removed in later releases
        guard let legacy = fileStorage.retrieve(Self.legacyStatusFile, as: PumpStatus.self) else { return }

        context.perform { [context, fileStorage] in
            let stored = PumpStatusStored(context: context)
            stored.date = legacy.timestamp ?? Date()
            stored.basalDeliveryState = (legacy.suspended ? PumpStatusStored.DeliveryState.suspended : .active).rawValue
            do {
                try context.save()
                fileStorage?.remove(Self.legacyStatusFile)
                debug(.storage, "Legacy pump status migrated: \(legacy.status.rawValue)")
            } catch {
                context.rollback()
                warning(.storage, "Migrating the legacy pump status failed", error: error)
            }
        }
    }
}

extension PumpStatusStored.DeliveryState {
    init(_ basalDeliveryState: PumpManagerStatus.BasalDeliveryState?) {
        switch basalDeliveryState {
        case .none:
            self = .unknown
        case let .active(since) where since == .distantPast:
            self = .inactive
        case .suspending:
            self = .suspending
        case .suspended:
            self = .suspended
        case .resuming:
            self = .resuming
        case .active,
             .cancelingTempBasal,
             .initiatingTempBasal,
             .tempBasal:
            self = .active
        }
    }
}

import CoreData
import Foundation
import LoopKit
import Swinject

protocol PumpStatusStorage {
    /// Stores the status when its delivery state or uncertainty differs from the last stored status.
    func storePumpStatus(_ status: PumpManagerStatus)
    /// Stores an unknown delivery state for a removed pump.
    func storePumpRemoved()
    func lastPumpStatus() async -> PumpStatus?
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
        removeLegacyStatusFile()
    }

    func storePumpStatus(_ status: PumpManagerStatus) {
        store(Self.deliveryState(of: status), deliveryIsUncertain: status.deliveryIsUncertain)
    }

    func storePumpRemoved() {
        store(.unknown, deliveryIsUncertain: false)
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

    private func store(_ deliveryState: PumpStatusStored.DeliveryState, deliveryIsUncertain: Bool) {
        let date = Date()

        context.perform { [context] in
            do {
                if let last = try context.fetch(PumpStatusStored.fetchLast()).first,
                   last.deliveryState == deliveryState,
                   last.deliveryIsUncertain == deliveryIsUncertain
                {
                    return
                }

                let stored = PumpStatusStored(context: context)
                stored.date = date
                stored.basalDeliveryState = deliveryState.rawValue
                stored.deliveryIsUncertain = deliveryIsUncertain
                try context.save()
                debug(.storage, "Pump status stored: \(deliveryState.rawValue), delivery uncertain \(deliveryIsUncertain)")
            } catch {
                context.rollback()
                warning(.storage, "Saving pump status failed", error: error)
            }
        }
    }

    private func removeLegacyStatusFile() { // FIXME: this can be removed in later releases
        guard let url = fileStorage.urlFor(file: Self.legacyStatusFile),
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        fileStorage.remove(Self.legacyStatusFile)
    }

    private static func deliveryState(of status: PumpManagerStatus) -> PumpStatusStored.DeliveryState {
        switch status.basalDeliveryState {
        case .none:
            return .unknown
        case let .active(since) where since == .distantPast:
            return .inactive
        case .suspending:
            return .suspending
        case .suspended:
            return .suspended
        case .resuming:
            return .resuming
        case .active,
             .cancelingTempBasal,
             .initiatingTempBasal,
             .tempBasal:
            return .active
        }
    }
}

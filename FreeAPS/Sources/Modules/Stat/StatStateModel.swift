import CoreData
import Foundation
import SwiftUI
import Swinject

extension Stat {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Published var highLimit: Decimal = 10 / 0.0555
        @Published var lowLimit: Decimal = 4 / 0.0555
        @Published var overrideUnit: Bool = false
        @Published var layingChart: Bool = false
        @Published var units: GlucoseUnits = .mmolL
        @Published var glucoseFromPersistence: [GlucoseStored] = []

        private let context = CoreDataStack.shared.newTaskContext()
        private let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            setupNotifications()
            setupGlucoseArray()
            highLimit = settingsManager.settings.high
            lowLimit = settingsManager.settings.low
            units = settingsManager.settings.units
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            layingChart = settingsManager.settings.oneDimensionalGraph
        }

        private func setupNotifications() {
            /// custom notification that is sent when a batch insert of glucose objects is done
            Foundation.NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBatchInsert),
                name: .didPerformBatchInsert,
                object: nil
            )
        }

        @objc private func handleBatchInsert() {
            setupGlucoseArray()
        }

        private func setupGlucoseArray() {
            Task {
                let ids = await self.fetchGlucose()
                await updateGlucoseArray(with: ids)
            }
        }

        private func fetchGlucose() async -> [NSManagedObjectID] {
            CoreDataStack.shared.fetchEntities(
                ofType: GlucoseStored.self,
                onContext: context,
                predicate: NSPredicate.glucose,
                key: "date",
                ascending: false,
                fetchLimit: 288
            ).map(\.objectID)
        }

        @MainActor private func updateGlucoseArray(with IDs: [NSManagedObjectID]) {
            do {
                let glucoseObjects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? GlucoseStored
                }
                glucoseFromPersistence = glucoseObjects
            } catch {
                debugPrint(
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error.localizedDescription)"
                )
            }
        }
    }
}

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
        @Published var units: GlucoseUnits = .mgdL
        @Published var glucoseFromPersistence: [GlucoseStored] = []

        @Published var selectedDuration: Duration = .Today

        private let context = CoreDataStack.shared.newTaskContext()
        private let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        enum Duration: String, CaseIterable, Identifiable {
            case Today
            case Day
            case Week
            case Month
            case Total
            var id: Self { self }
        }

        override func subscribe() {
            /// Default is today
            setupGlucoseArray(for: .Today)
            highLimit = settingsManager.settings.high
            lowLimit = settingsManager.settings.low
            units = settingsManager.settings.units
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            layingChart = settingsManager.settings.oneDimensionalGraph
        }

        func setupGlucoseArray(for duration: Duration) {
            Task {
                let ids = await self.fetchGlucose(for: duration)
                await updateGlucoseArray(with: ids)
            }
        }

        private func fetchGlucose(for duration: Duration) async -> [NSManagedObjectID] {
            let predicate: NSPredicate

            switch duration {
            case .Day:
                predicate = NSPredicate.glucoseForStatsDay
            case .Week:
                predicate = NSPredicate.glucoseForStatsWeek
            case .Today:
                predicate = NSPredicate.glucoseForStatsToday
            case .Month:
                predicate = NSPredicate.glucoseForStatsMonth
            case .Total:
                predicate = NSPredicate.glucoseForStatsTotal
            }

            let results = await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: GlucoseStored.self,
                onContext: context,
                predicate: predicate,
                key: "date",
                ascending: false,
                batchSize: 100,
                propertiesToFetch: ["glucose", "date"]
            )

            guard let fetchedResults = results as? [GlucoseStored] else { return [] }

            return await context.perform {
                return fetchedResults.map(\.objectID)
            }
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

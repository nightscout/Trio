import CoreData
import Foundation
import Observation
import SwiftUI
import Swinject

extension Stat {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var settings: SettingsManager!
        var highLimit: Decimal = 10 / 0.0555
        var lowLimit: Decimal = 4 / 0.0555
        var hbA1cDisplayUnit: HbA1cDisplayUnit = .percent
        var timeInRangeChartStyle: TimeInRangeChartStyle = .vertical
        var units: GlucoseUnits = .mgdL
        var glucoseFromPersistence: [GlucoseStored] = []

        var selectedDuration: Duration = .Today

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
            hbA1cDisplayUnit = settingsManager.settings.hbA1cDisplayUnit
            timeInRangeChartStyle = settingsManager.settings.timeInRangeChartStyle
        }

        func setupGlucoseArray(for duration: Duration) {
            Task {
                let ids = await self.fetchGlucose(for: duration)
                await updateGlucoseArray(with: ids)
            }
        }

        private func fetchGlucose(for duration: Duration) async -> [NSManagedObjectID] {
            do {
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

                let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                    ofType: GlucoseStored.self,
                    onContext: context,
                    predicate: predicate,
                    key: "date",
                    ascending: false,
                    batchSize: 100,
                    propertiesToFetch: ["glucose", "objectID"]
                )

                return try await context.perform {
                    guard let fetchedResults = results as? [[String: Any]] else {
                        throw CoreDataError.fetchError(function: #function, file: #file)
                    }
                    return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Error fetching glucose for stats: \(error.localizedDescription)")
                return []
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

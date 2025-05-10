import CoreData
import Observation
import SwiftDate
import SwiftUI

extension Calibrations {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var glucoseStorage: GlucoseStorage!
        @ObservationIgnored @Injected() var calibrationService: CalibrationService!

        var slope: Double = 1
        var intercept: Double = 1
        var newCalibration: Decimal = 0
        var calibrations: [Calibration] = []
        var calibrate: (Int) -> Double = { Double($0) }
        var items: [Item] = []

        var units: GlucoseUnits = .mgdL

        let backgroundContext = CoreDataStack.shared.newTaskContext()
        private let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            units = settingsManager.settings.units
            calibrate = calibrationService.calibrate
            setupCalibrations()
        }

        private func setupCalibrations() {
            slope = calibrationService.slope
            intercept = calibrationService.intercept
            calibrations = calibrationService.calibrations
            items = calibrations.map {
                Item(calibration: $0)
            }
        }

        /// - Returns: An array of NSManagedObjectIDs for glucose readings.
        private func fetchGlucose() async throws -> [NSManagedObjectID] {
            let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: GlucoseStored.self,
                onContext: backgroundContext,
                predicate: NSPredicate.predicateFor20MinAgo,
                key: "date",
                ascending: false,
                fetchLimit: 1 /// We only need the last value
            )

            return try await backgroundContext.perform {
                guard let glucoseResults = results as? [GlucoseStored] else {
                    throw CoreDataError.fetchError(function: #function, file: #file)
                }

                return glucoseResults.map(\.objectID)
            }
        }

        @MainActor func addCalibration() async {
            do {
                defer {
                    UIApplication.shared.endEditing()
                    setupCalibrations()
                }

                var glucose = newCalibration
                if units == .mmolL {
                    glucose = newCalibration.asMgdL
                }

                let glucoseValuesIds = try await fetchGlucose()
                let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: glucoseValuesIds, context: viewContext)

                if let lastGlucose = glucoseObjects.first {
                    let unfiltered = lastGlucose.glucose
                    let calibration = Calibration(x: Double(unfiltered), y: Double(glucose))

                    calibrationService.addCalibration(calibration)
                } else {
                    info(.service, "Glucose is stale for calibration")
                    return
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Failed to add calibration: \(error)")
            }
        }

        func removeLast() {
            calibrationService.removeLast()
            setupCalibrations()
        }

        func removeAll() {
            calibrationService.removeAllCalibrations()
            setupCalibrations()
        }

        func removeAtIndex(_ index: Int) {
            let calibration = calibrations[index]
            calibrationService.removeCalibration(calibration)
            setupCalibrations()
        }
    }
}

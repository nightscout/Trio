import SwiftDate
import SwiftUI

extension Calibrations {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var calibrationService: CalibrationService!

        @Published var slope: Double = 1
        @Published var intercept: Double = 1
        @Published var newCalibration: Decimal = 0
        @Published var calibrations: [Calibration] = []
        @Published var calibrate: (Double) -> Double = { $0 }
        @Published var items: [Item] = []

        var units: GlucoseUnits = .mgdL

        // TODO: - test if we need to use the viewContext here
        private let context = CoreDataStack.shared.newTaskContext()

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

        private func fetchAndProcessGlucose() -> GlucoseStored? {
            do {
                debugPrint("Calibrations State Model: \(#function) \(DebuggingIdentifiers.succeeded) fetched glucose")
                return try context.fetch(GlucoseStored.fetch(
                    NSPredicate.predicateFor20MinAgo,
                    ascending: false,
                    fetchLimit: 1
                )).first
            } catch {
                debugPrint("Calibrations State Model: \(#function) \(DebuggingIdentifiers.failed) failed to fetch glucose")
                return nil
            }
        }

        func addCalibration() {
            defer {
                UIApplication.shared.endEditing()
                setupCalibrations()
            }

            var glucose = newCalibration
            if units == .mmolL {
                glucose = newCalibration.asMgdL
            }

            if let lastGlucose = fetchAndProcessGlucose() {
                let unfiltered = lastGlucose.glucose

                let calibration = Calibration(x: Double(unfiltered), y: Double(glucose))

                calibrationService.addCalibration(calibration)
            } else {
                info(.service, "Glucose is stale for calibration")
                return
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

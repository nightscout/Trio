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
        @Published var calibrate: (Int) -> Double = { Double($0) }
        @Published var items: [Item] = []

        var units: GlucoseUnits = .mmolL

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

        func addCalibration() {
            defer {
                UIApplication.shared.endEditing()
                setupCalibrations()
            }

            var glucose = newCalibration
            if units == .mmolL {
                glucose = newCalibration.asMgdL
            }

            guard let lastGlucose = glucoseStorage.recent().last,
                  lastGlucose.dateString.addingTimeInterval(60 * 4.5) > Date(),
                  let unfiltered = lastGlucose.unfiltered
            else {
                info(.service, "Glucose is stale for calibration")
                return
            }

            let calibration = Calibration(x: Double(unfiltered), y: Double(glucose))

            calibrationService.addCalibration(calibration)
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

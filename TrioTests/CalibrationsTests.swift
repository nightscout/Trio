import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("Calibration Service Tests", .serialized) struct CalibrationTests: Injectable {
    let fileStorage = BaseFileStorage()
    @Injected() var calibrationService: CalibrationService!
    let resolver = TrioApp().resolver

    init() {
        injectServices(resolver)
    }

    @Test("Can create simple calibration") func testCreateSimpleCalibration() {
        // Given
        calibrationService.removeAllCalibrations()
        let calibration = Calibration(x: 100.0, y: 102.0)

        // When
        calibrationService.addCalibration(calibration)

        // Then
        #expect(calibrationService.calibrations.isNotEmpty)
        #expect(calibrationService.slope == 1)
        #expect(calibrationService.intercept == 2)
        #expect(calibrationService.calibrate(value: 104) == 106)
    }

    @Test("Can handle multiple calibrations") func testCreateMultipleCalibration() {
        // Given
        calibrationService.removeAllCalibrations()
        let calibration = Calibration(x: 100.0, y: 120)
        let calibration2 = Calibration(x: 120.0, y: 130.0)

        // When
        calibrationService.addCalibration(calibration)
        calibrationService.addCalibration(calibration2)

        // Then
        #expect(abs(calibrationService.slope - 0.8) < 0.0001)
        #expect(abs(calibrationService.intercept - 37) < 0.0001)
        #expect(abs(calibrationService.calibrate(value: 80) - 101) < 0.0001)

        // When removing last
        calibrationService.removeLast()
        #expect(calibrationService.calibrations.count == 1)

        // When removing all
        calibrationService.removeAllCalibrations()
        #expect(calibrationService.calibrations.isEmpty)
    }

    @Test("Handles calibration bounds correctly") func testCalibrationBounds() {
        // Given
        calibrationService.removeAllCalibrations()

        // When no calibrations exist
        #expect(calibrationService.slope == 1, "Default slope should be 1")
        #expect(calibrationService.intercept == 0, "Default intercept should be 0")

        // When adding extreme values
        let extremeCalibration1 = Calibration(x: 0.0, y: 1000.0) // Should be clamped
        let extremeCalibration2 = Calibration(x: 1000.0, y: 0.0) // Should be clamped

        calibrationService.addCalibration(extremeCalibration1)
        calibrationService.addCalibration(extremeCalibration2)

        // Then check bounds
        #expect(calibrationService.slope >= 0.8, "Slope should not be less than minimum")
        #expect(calibrationService.slope <= 1.25, "Slope should not be more than maximum")
        #expect(calibrationService.intercept >= -100, "Intercept should not be less than minimum")
        #expect(calibrationService.intercept <= 100, "Intercept should not be more than maximum")
    }
}

@Suite("Calibration Service Concurrency Tests") struct CalibrationConcurrencyTests {
    let resolver = TrioApp().resolver

    @Test("Concurrent calibrate and remove all do not race") func testConcurrentCalibrateAndRemoveAll() {
        let service = BaseCalibrationService(resolver: resolver)
        service.removeAllCalibrations()

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            switch index % 3 {
            case 0:
                service.addCalibration(Calibration(x: 100.0, y: 110.0))
            case 1:
                service.removeAllCalibrations()
            default:
                let value = service.calibrate(value: 120)
                #expect(value >= 0 && value <= 500)
            }
        }

        service.removeAllCalibrations()
        #expect(service.calibrations.isEmpty)
    }
}

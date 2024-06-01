@testable import FreeAPS
import Swinject
import XCTest

class CalibrationsTests: XCTestCase, Injectable {
    let fileStorage = BaseFileStorage()
    @Injected() var calibrationService: CalibrationService!
    let resolver = FreeAPSApp().resolver

    override func setUp() {
        injectServices(resolver)
    }

    func testCreateSimpleCalibration() {
        // restore state so each test is independent
        calibrationService.removeAllCalibrations()

        let calibration = Calibration(x: 100.0, y: 102.0)
        calibrationService.addCalibration(calibration)

        XCTAssertTrue(calibrationService.calibrations.isNotEmpty)

        XCTAssertTrue(calibrationService.slope == 1)

        XCTAssertTrue(calibrationService.intercept == 2)

        XCTAssertTrue(calibrationService.calibrate(value: 104) == 106)
    }

    func testCreateMultipleCalibration() {
        // restore state so each test is independent
        calibrationService.removeAllCalibrations()

        let calibration = Calibration(x: 100.0, y: 120)
        calibrationService.addCalibration(calibration)

        let calibration2 = Calibration(x: 120.0, y: 130.0)
        calibrationService.addCalibration(calibration2)

        XCTAssertEqual(calibrationService.slope, 0.8, accuracy: 0.0001)
        XCTAssertEqual(calibrationService.intercept, 37, accuracy: 0.0001)
        XCTAssertEqual(calibrationService.calibrate(value: 80), 101, accuracy: 0.0001)

        calibrationService.removeLast()

        XCTAssertTrue(calibrationService.calibrations.count == 1)

        calibrationService.removeAllCalibrations()
        XCTAssertTrue(calibrationService.calibrations.isEmpty)
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
}

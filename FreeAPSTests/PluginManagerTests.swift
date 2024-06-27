@testable import FreeAPS
import Swinject
import XCTest

class PluginManagerTests: XCTestCase, Injectable {
    let fileStorage = BaseFileStorage()
    @Injected() var pluginManager: PluginManager!
    let resolver = FreeAPSApp().resolver

    override func setUp() {
        injectServices(resolver)
    }

    func testCGMManagerLoad() {
        let cgmLoopManagers = pluginManager.availableCGMManagers
        XCTAssertNotNil(cgmLoopManagers)
        XCTAssertTrue(!cgmLoopManagers.isEmpty)
        if let cgmLoop = cgmLoopManagers.first {
            let cgmLoopManager = pluginManager.getCGMManagerTypeByIdentifier(cgmLoop.identifier)
            XCTAssertNotNil(cgmLoopManager)
        } else {
            XCTFail("Not found CGM loop manager")
        }
        /// try to load a Pump manager with a CGM identifier
        if let cgmLoop = cgmLoopManagers.last {
            let cgmLoopManager = pluginManager.getPumpManagerTypeByIdentifier(cgmLoop.identifier)
            XCTAssertNil(cgmLoopManager)
        } else {
            XCTFail("Not found CGM loop manager")
        }
    }

    func testPumpManagerLoad() {
        let pumpLoopManagers = pluginManager.availablePumpManagers
        XCTAssertNotNil(pumpLoopManagers)
        XCTAssertTrue(!pumpLoopManagers.isEmpty)
        if let pumpLoop = pumpLoopManagers.first {
            let pumpLoopManager = pluginManager.getPumpManagerTypeByIdentifier(pumpLoop.identifier)
            XCTAssertNotNil(pumpLoopManager)
        } else {
            XCTFail("Not found pump loop manager")
        }
        /// try to load a CGM manager with a pump identifier
        if let pumpLoop = pumpLoopManagers.last {
            let pumpLoopManager = pluginManager.getCGMManagerTypeByIdentifier(pumpLoop.identifier)
            XCTAssertNil(pumpLoopManager)
        } else {
            XCTFail("Not found pump loop manager")
        }
    }

    func testServiceManagerLoad() {
        let serviceManagers = pluginManager.availableServices
        XCTAssertNotNil(serviceManagers)
        XCTAssertTrue(!serviceManagers.isEmpty)
        if let serviceLoop = serviceManagers.first {
            let serviceManager = pluginManager.getServiceTypeByIdentifier(serviceLoop.identifier)
            XCTAssertNotNil(serviceManager)
        } else {
            XCTFail("Not found Service loop manager")
        }
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
}

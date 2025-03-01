import Foundation
import Swinject
import Testing
@testable import Trio

@Suite("Plugin Manager Tests", .serialized) struct PluginManagerTests: Injectable {
    let fileStorage = BaseFileStorage()
    @Injected() var pluginManager: PluginManager!
    let resolver = TrioApp().resolver

    init() {
        injectServices(resolver)
    }

    @Test("Can load CGM managers") func testCGMManagerLoad() {
        // Given
        let cgmLoopManagers = pluginManager.availableCGMManagers

        // Then
        #expect(!cgmLoopManagers.isEmpty, "Should have available CGM managers")

        // When loading valid CGM manager
        if let cgmLoop = cgmLoopManagers.first {
            let cgmLoopManager = pluginManager.getCGMManagerTypeByIdentifier(cgmLoop.identifier)
            #expect(cgmLoopManager != nil, "Should load valid CGM manager")
        }

        // When trying to load CGM manager with pump identifier
        if let cgmLoop = cgmLoopManagers.last {
            let invalidManager = pluginManager.getPumpManagerTypeByIdentifier(cgmLoop.identifier)
            #expect(invalidManager == nil, "Should not load CGM manager with pump identifier")
        }
    }

    @Test("Can load pump managers") func testPumpManagerLoad() {
        // Given
        let pumpLoopManagers = pluginManager.availablePumpManagers

        // Then
        #expect(!pumpLoopManagers.isEmpty, "Should have available pump managers")

        // When loading valid pump manager
        if let pumpLoop = pumpLoopManagers.first {
            let pumpLoopManager = pluginManager.getPumpManagerTypeByIdentifier(pumpLoop.identifier)
            #expect(pumpLoopManager != nil, "Should load valid pump manager")
        }

        // When trying to load pump manager with CGM identifier
        if let pumpLoop = pumpLoopManagers.last {
            let invalidManager = pluginManager.getCGMManagerTypeByIdentifier(pumpLoop.identifier)
            #expect(invalidManager == nil, "Should not load pump manager with CGM identifier")
        }
    }

    @Test("Can load service managers") func testServiceManagerLoad() {
        // Given
        let serviceManagers = pluginManager.availableServices

        // Then
        #expect(!serviceManagers.isEmpty, "Should have available services")

        // When
        if let serviceLoop = serviceManagers.first {
            let serviceManager = pluginManager.getServiceTypeByIdentifier(serviceLoop.identifier)
            #expect(serviceManager != nil, "Should load valid service manager")
        }
    }

    @Test("Available managers have valid descriptors") func testManagerDescriptors() {
        // Given/When
        let pumpManagers = pluginManager.availablePumpManagers
        let cgmManagers = pluginManager.availableCGMManagers
        let serviceManagers = pluginManager.availableServices

        // Then
        for manager in pumpManagers {
            #expect(!manager.identifier.isEmpty, "Pump manager should have non-empty identifier")
            #expect(!manager.localizedTitle.isEmpty, "Pump manager should have non-empty title")
        }

        for manager in cgmManagers {
            #expect(!manager.identifier.isEmpty, "CGM manager should have non-empty identifier")
            #expect(!manager.localizedTitle.isEmpty, "CGM manager should have non-empty title")
        }

        for manager in serviceManagers {
            #expect(!manager.identifier.isEmpty, "Service should have non-empty identifier")
            #expect(!manager.localizedTitle.isEmpty, "Service should have non-empty title")
        }
    }
}

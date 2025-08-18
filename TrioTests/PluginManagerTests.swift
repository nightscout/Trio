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
    }

    @Test("Available managers have valid descriptors") func testManagerDescriptors() {
        // Given/When
        let cgmManagers = pluginManager.availableCGMManagers

        for manager in cgmManagers {
            #expect(!manager.identifier.isEmpty, "CGM manager should have non-empty identifier")
            #expect(!manager.localizedTitle.isEmpty, "CGM manager should have non-empty title")
        }
    }
}

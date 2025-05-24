//
// Trio
// PluginManagerTests.swift
// Created by Deniz Cengiz on 2025-01-05.
// Last edited by Marvin Polscheit on 2025-05-24.
// Most contributions by Marvin Polscheit and Pierre L.
//
// Documentation available under: https://triodocs.org/

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

    @Test("Can load CGM managers") func cGMManagerLoad() {
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

    @Test("Available managers have valid descriptors") func managerDescriptors() {
        // Given/When
        let cgmManagers = pluginManager.availableCGMManagers

        for manager in cgmManagers {
            #expect(!manager.identifier.isEmpty, "CGM manager should have non-empty identifier")
            #expect(!manager.localizedTitle.isEmpty, "CGM manager should have non-empty title")
        }
    }
}

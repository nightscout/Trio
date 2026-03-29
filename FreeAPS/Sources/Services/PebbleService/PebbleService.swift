//
//  PebbleService.swift
//  Trio
//
//  Created by Orka on 2026-03-28.
//  Copyright © 2026 Trio Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI
import os.log

/// Manages Pebble smartwatch integration for Trio
/// Runs local HTTP server to expose CGM/pump data to Pebble via Bluetooth
/// Supports bolus and carb commands with iOS confirmation
final class PebbleService: Injectable {
    
    // MARK: - Dependencies
    
    @Injected() var broadcaster: Broadcaster!
    @Injected() var storage: FileStorage!
    @Injected() var cgmManager: CGMManager!
    @Injected() var pumpManager: PumpManager!
    
    // MARK: - Properties
    
    private let log = OSLog(category: "PebbleService")
    private let dataBridge = TrioDataBridge()
    private let commandManager = PebbleCommandManager.shared
    private var apiServer: LocalAPIServer!
    
    // MARK: - Configuration
    
    /// Default port for Pebble API
    private static let defaultPort: UInt16 = 8080
    
    /// Alternative ports if default is in use
    private static let alternativePorts: [UInt16] = [8081, 8082, 8083, 8084, 8085]
    
    /// User defaults key for storing port preference
    private let portUserDefaultsKey = "PebbleAPIPort"
    
    /// Currently configured port
    private var configuredPort: UInt16 = defaultPort
    
    /// Server state
    private var isStarted = false
    
    // MARK: - Initialization
    
    public init(resolver: Resolver) {
        injectServices(resolver)
        
        // Load saved port from UserDefaults
        if let savedPort = UserDefaults.standard.object(forKey: portUserDefaultsKey) as? UInt16 {
            configuredPort = savedPort
        }
        
        log.default("PebbleService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Start Pebble integration
    /// Begins local HTTP server for off-grid communication
    func start() {
        guard !isStarted else {
            log.info("PebbleService already started")
            return
        }
        
        log.info("Starting PebbleService")
        
        // Initialize API server with configured port
        apiServer = LocalAPIServer(dataBridge: dataBridge, 
                                 commandManager: commandManager, 
                                 port: configuredPort)
        
        apiServer.start()
        isStarted = true
        
        // Subscribe to CGM updates
        broadcaster.register(observer: self, 
                           notification: .cgmManagerDidUpdateGlucose) { [weak self] _ in
            self?.handleCGMUpdate()
        }
        
        // Subscribe to pump updates
        broadcaster.register(observer: self,
                           notification: .pumpManagerDidUpdatePumpState) { [weak self] _ in
            self?.handlePumpUpdate()
        }
        
        log.info("PebbleService started - API available at http://127.0.0.1:\(configuredPort)")
        log.info(LocalAPIServer.apiDocumentation)
    }
    
    /// Stop Pebble service
    func stop() {
        guard isStarted else { return }
        
        log.info("Stopping PebbleService")
        
        apiServer.stop()
        isStarted = false
        
        // Unregister from broadcasts
        broadcaster.unregister(observer: self)
    }
    
    // MARK: - Private Methods
    
    private func handleCGMUpdate() {
        guard let glucose = cgmManager.latestGlucose else { return }
        updatePebbleWithGlucose(glucose)
    }
    
    private func handlePumpUpdate() {
        guard let pumpState = pumpManager.pumpState else { return }
        updatePebbleWithInsulin(pumpState)
    }
    
    private func updatePebbleWithGlucose(_ glucose: Glucose) {
        let glucoseValue = glucose.sgv ?? glucose.glucose ?? 0
        let trend = glucose.direction?.rawValue ?? "none"
        let date = glucose.date
        
        dataBridge.updateGlucose(value: Double(glucoseValue),
                               unit: "mg/dL",
                               trend: trend,
                               date: date)
    }
    
    private func updatePebbleWithInsulin(_ pumpState: PumpState) {
        let iob = pumpState.insulinOnBoard
        let cob = pumpState.carbsOnBoard
        let reservoir = pumpState.reservoirAmount
        let battery = pumpState.batteryChargeRemaining
        
        dataBridge.updateInsulin(iob: iob?.doubleValue ?? 0,
                               cob: cob?.doubleValue ?? 0,
                               reservoir: reservoir?.doubleValue ?? 0,
                               battery: battery?.doubleValue ?? 0)
    }
    
    // MARK: - Configuration Methods
    
    /// Get current API port
    func getCurrentPort() -> UInt16 {
        return configuredPort
    }
    
    /// Set API port (requires restart to take effect)
    /// - Parameters:
    ///   - port: New port number (must be 1024-65535)
    ///   - restartNow: If true, restarts server immediately; if false, applies on next start
    /// - Returns: True if port was valid and set
    func setPort(_ port: UInt16, restartNow: Bool = false) -> Bool {
        // Validate port range
        guard port >= 1024 && port <= 65535 else {
            log.error("Invalid port number: \(port). Must be between 1024 and 65535")
            return false
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(port, forKey: portUserDefaultsKey)
        
        if port != configuredPort {
            let oldPort = configuredPort
            configuredPort = port
            
            log.info("Pebble API port changed from \(oldPort) to \(port)")
            
            if restartNow && isStarted {
                restart()
            }
        }
        
        return true
    }
    
    /// Restart Pebble service (useful after port change)
    func restart() {
        stop()
        // Clear the API server so it reinitializes with new port
        apiServer = nil
        start()
    }
    
    /// Get list of alternative ports for UI dropdown
    static func getAvailablePorts() -> [UInt16] {
        return [PebbleService.defaultPort] + PebbleService.alternativePorts
    }
}

// MARK: - PebbleCommandConfirmationDelegate

extension PebbleService: PebbleCommandConfirmationDelegate {
    func pendingCommandRequiresConfirmation(_ command: PebbleCommand) {
        log.default("Pebble command requires confirmation: \(command.confirmationMessage)")
        
        // This will be handled by the UI layer - the command manager
        // already has the confirmation delegate set
        // The actual UI presentation happens in the main app
    }
    
    func commandExecuted(_ command: PebbleCommand) {
        log.default("PebbleCommand executed successfully: \(command.type.rawValue)")
    }
    
    func commandFailed(_ command: PebbleCommand, error: String) {
        log.error("PebbleCommand failed: \(command.id) - Error: \(error)")
    }
}

// MARK: - Local API Server Integration

extension PebbleService {
    /// Update Pebble with new glucose data
    func updatePebbleWithGlucose(_ glucose: Double, trend: String?, date: Date?) {
        dataBridge.updateGlucose(value: glucose, unit: "mg/dL", trend: trend, date: date)
    }
    
    /// Update Pebble with insulin data
    func updatePebbleWithInsulin(iob: Double?, cob: Double?, reservoir: Double?, battery: Double?) {
        dataBridge.updateInsulin(iob: iob, cob: cob, reservoir: reservoir, reservoirPercent: battery)
    }
    
    /// Update Pebble with pump status
    func updatePebbleWithPump(battery: Double?) {
        dataBridge.updatePump(battery: battery)
    }
    
    /// Update Pebble with loop status
    func updatePebbleWithLoopStatus(automaticDosing: Bool, lastRun: Date?, recommendedBolus: Double?, predicted: [Double]?) {
        dataBridge.updateLoopStatus(
            isClosedLoop: automaticDosing,
            lastRun: lastRun,
            recommendedBolus: recommendedBolus,
            predicted: predicted
        )
    }
}

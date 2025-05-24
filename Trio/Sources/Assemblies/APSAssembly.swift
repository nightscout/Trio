//
// Trio
// APSAssembly.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Vasiliy Usov and Pierre L.
//
// Documentation available under: https://triodocs.org/

import Foundation
import Swinject

final class APSAssembly: Assembly {
    func assemble(container: Container) {
        container.register(DeviceDataManager.self) { r in BaseDeviceDataManager(resolver: r) }
        container.register(APSManager.self) { r in BaseAPSManager(resolver: r) }
        container.register(FetchGlucoseManager.self) { r in BaseFetchGlucoseManager(resolver: r) }
        container.register(FetchTreatmentsManager.self) { r in BaseFetchTreatmentsManager(resolver: r) }
        container.register(BluetoothStateManager.self) { r in BaseBluetoothStateManager(resolver: r) }
        container.register(PluginManager.self) { r in BasePluginManager(resolver: r) }
        container.register(CalibrationService.self) { r in BaseCalibrationService(resolver: r) }
    }
}

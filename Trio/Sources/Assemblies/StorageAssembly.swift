//
// Trio
// StorageAssembly.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-02-07.
// Most contributions by Vasiliy Usov and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import Foundation
import Swinject

final class StorageAssembly: Assembly {
    func assemble(container: Container) {
        container.register(FileManager.self) { _ in
            Foundation.FileManager.default
        }
        container.register(FileStorage.self) { _ in BaseFileStorage() }
        container.register(PumpHistoryStorage.self) { r in BasePumpHistoryStorage(resolver: r) }
        container.register(OverrideStorage.self) { r in BaseOverrideStorage(resolver: r) }
        container.register(DeterminationStorage.self) { r in BaseDeterminationStorage(resolver: r) }
        container.register(TDDStorage.self) { r in BaseTDDStorage(resolver: r) }
        container.register(GlucoseStorage.self) { r in BaseGlucoseStorage(resolver: r) }
        container.register(TempTargetsStorage.self) { r in BaseTempTargetsStorage(resolver: r) }
        container.register(CarbsStorage.self) { r in BaseCarbsStorage(resolver: r) }
        container.register(ContactImageStorage.self) { r in BaseContactImageStorage(resolver: r) }
        container.register(SettingsManager.self) { r in BaseSettingsManager(resolver: r) }
        container.register(Keychain.self) { _ in BaseKeychain() }
        container.register(AlertHistoryStorage.self) { r in BaseAlertHistoryStorage(resolver: r) }
    }
}

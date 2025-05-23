// Trio
// SecurityAssembly.swift
// Created by Vasiliy Usov on 2021-11-07.

import Foundation
import Swinject

final class SecurityAssembly: Assembly {
    func assemble(container: Container) {
        container.register(UnlockManager.self) { _ in BaseUnlockManager() }
    }
}

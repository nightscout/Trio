//
// Trio
// SecurityAssembly.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Vasiliy Usov.
//
// Documentation available under: https://triodocs.org/

import Foundation
import Swinject

final class SecurityAssembly: Assembly {
    func assemble(container: Container) {
        container.register(UnlockManager.self) { _ in BaseUnlockManager() }
    }
}

//
// Trio
// UIAssembly.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Vasiliy Usov.
//
// Documentation available under: https://triodocs.org/

import Foundation
import Swinject

final class UIAssembly: Assembly {
    func assemble(container: Container) {
        container.register(AppearanceManager.self) { _ in BaseAppearanceManager() }
        container.register(Router.self) { r in BaseRouter(resolver: r) }
    }
}

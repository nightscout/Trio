// Trio
// UIAssembly.swift
// Created by Vasiliy Usov on 2021-11-07.

import Foundation
import Swinject

final class UIAssembly: Assembly {
    func assemble(container: Container) {
        container.register(AppearanceManager.self) { _ in BaseAppearanceManager() }
        container.register(Router.self) { r in BaseRouter(resolver: r) }
    }
}

// Trio
// NetworkAssembly.swift
// Created by Vasiliy Usov on 2021-11-07.

import Foundation
import Swinject

final class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(ReachabilityManager.self) { _ in
            NetworkReachabilityManager()!
        }

        container.register(NightscoutManager.self) { r in BaseNightscoutManager(resolver: r) }
        container.register(TidepoolManager.self) { r in BaseTidepoolManager(resolver: r) }
    }
}

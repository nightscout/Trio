//
// Trio
// NetworkAssembly.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Vasiliy Usov and Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

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

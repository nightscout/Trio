//
// Trio
// BaseProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and avouspierre.
//
// Documentation available under: https://triodocs.org/

import Combine
import Foundation
import Swinject

protocol Provider {
    init(resolver: Resolver)
}

class BaseProvider: Provider, Injectable {
    var lifetime = Lifetime()
    @Injected() var deviceManager: DeviceDataManager!
    @Injected() var storage: FileStorage!
    @Injected() var bluetoothProvider: BluetoothStateManager!

    required init(resolver: Resolver) {
        injectServices(resolver)
    }
}

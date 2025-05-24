//
// Trio
// NightscoutConfigDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Ivan.
//
// Documentation available under: https://triodocs.org/

import Combine
import Foundation

enum NightscoutConfig {
    enum Config {
        static let urlKey = "NightscoutConfig.url"
        static let secretKey = "NightscoutConfig.secret"
    }
}

protocol NightscoutConfigProvider: Provider {
    func checkConnection(url: URL, secret: String?) -> AnyPublisher<Void, Error>
}

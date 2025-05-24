//
// Trio
// ReachabilityManager.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan.
//
// Documentation available under: https://triodocs.org/

import Foundation

typealias ReachabilityStatus = NetworkReachabilityManager.NetworkReachabilityStatus
typealias Listener = NetworkReachabilityManager.Listener

protocol ReachabilityManager: AnyObject {
    var status: ReachabilityStatus { get }
    var isReachable: Bool { get }
    func startListening(onQueue: DispatchQueue, onUpdatePerforming: @escaping Listener) -> Bool
    func stopListening()
}

extension NetworkReachabilityManager: ReachabilityManager {}

extension ReachabilityStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .notReachable:
            return "NOT reachable"
        case let .reachable(connectionType):
            return "reachable by " + (connectionType == .cellular ? "Cellular" : "WiFi")
        }
    }
}

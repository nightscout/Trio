//
// Trio
// GlucoseSource.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Pierre L.
//
// Documentation available under: https://triodocs.org/

import Combine
import LoopKit
import LoopKitUI

protocol SourceInfoProvider {
    func sourceInfo() -> [String: Any]?
}

protocol GlucoseSource: SourceInfoProvider {
    func fetch(_ heartbeat: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never>
    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never>
    var glucoseManager: FetchGlucoseManager? { get set }
    var cgmManager: CGMManagerUI? { get set }
}

extension GlucoseSource {
    func sourceInfo() -> [String: Any]? { nil }
}

//
// Trio
// AdjustmentsDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-02-19.
// Most contributions by Marvin Polscheit and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SwiftUI

enum Adjustments {
    enum Config {}

    enum Tab: String, Hashable, Identifiable, CaseIterable {
        case overrides
        case tempTargets

        var id: String { rawValue }

        var name: String {
            switch self {
            case .overrides:
                return String(localized: "Overrides", comment: "Selected Tab")
            case .tempTargets:
                return String(localized: "Temp Targets", comment: "Selected Tab")
            }
        }
    }
}

protocol AdjustmentsProvider: Provider {}

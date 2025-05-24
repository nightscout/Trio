//
// Trio
// LoopUIColorPalette+Default.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by avouspierre and Pierre L.
//
// Documentation available under: https://triodocs.org/

import LoopKitUI
import SwiftUI

extension StateColorPalette {
    static let loopStatus = StateColorPalette(
        unknown: .unknownColor,
        normal: .freshColor,
        warning: .agingColor,
        error: .staleColor
    )

    static let cgmStatus = loopStatus

    static let pumpStatus = StateColorPalette(
        unknown: .unknownColor,
        normal: .pumpStatusNormal,
        warning: .agingColor,
        error: .staleColor
    )
}

extension ChartColorPalette {
    static var primary: ChartColorPalette {
        ChartColorPalette(
            axisLine: .axisLineColor,
            axisLabel: .axisLabelColor,
            grid: .gridColor,
            glucoseTint: .glucoseTintColor,
            insulinTint: .insulinTintColor,
            carbTint: .carbTintColor
        )
    }
}

public extension GuidanceColors {
    static var `default`: GuidanceColors {
        GuidanceColors(acceptable: .primary, warning: .warning, critical: .critical)
    }
}

public extension LoopUIColorPalette {
    static var `default`: LoopUIColorPalette {
        LoopUIColorPalette(
            guidanceColors: .default,
            carbTintColor: .carbTintColor,
            glucoseTintColor: .glucoseTintColor,
            insulinTintColor: .insulinTintColor,
            loopStatusColorPalette: .loopStatus,
            chartColorPalette: .primary
        )
    }
}

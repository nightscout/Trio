//
// Trio
// Decimal+Extensions.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import CoreGraphics
import Foundation

extension Double {
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSNumber)
    }
}

extension Int {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

extension Int16 {
    var minutes: TimeInterval {
        TimeInterval(self) * 60
    }
}

extension CGFloat {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

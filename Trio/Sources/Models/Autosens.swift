//
// Trio
// Autosens.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct Autosens: JSON {
    let ratio: Decimal
    let newisf: Decimal?
    var timestamp: Date?
}

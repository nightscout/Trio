// Trio
// String+Extensions.swift
// Created by Ivan Valkou on 2021-03-07.

import Foundation

extension String {
    func capitalizingFirstLetter() -> String {
        prefix(1).capitalized + dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = capitalizingFirstLetter()
    }
}

extension LosslessStringConvertible {
    var string: String { .init(self) }
}

extension FloatingPoint where Self: LosslessStringConvertible {
    var decimal: Decimal? { Decimal(string: string) }
}

//
// Trio
// Array+Extension.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon B.M.
//
// Documentation available under: https://triodocs.org/

extension Array where Element: Hashable {
    func removeDublicates() -> Self {
        var result = Self()
        for item in self {
            if !result.contains(item) {
                result.append(item)
            }
        }
        return result
    }
}

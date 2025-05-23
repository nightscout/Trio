// Trio
// Array+Extension.swift
// Created by Jon B.M on 2021-12-05.

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

// Trio
// AutotuneConfigDataFlow.swift
// Created by Ivan Valkou on 2021-03-13.

import Combine

enum AutotuneConfig {
    enum Config {}
}

protocol AutotuneConfigProvider: Provider {
    var autotune: Autotune? { get }
    func deleteAutotune()
}

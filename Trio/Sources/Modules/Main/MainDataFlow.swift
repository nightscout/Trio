// Trio
// MainDataFlow.swift
// Created by Ivan Valkou on 2021-02-02.

import SwiftUI

enum Main {
    enum Config {}

    struct Modal: Identifiable {
        let screen: Screen
        let view: AnyView

        var id: Int { screen.id }
    }

    struct SecondaryModalWrapper: Identifiable {
        let id = UUID()
        let view: AnyView
    }
}

protocol MainProvider: Provider {}

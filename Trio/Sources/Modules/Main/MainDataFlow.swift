//
// Trio
// MainDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-05-12.
// Most contributions by Ivan Valkou and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

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

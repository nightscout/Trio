//
// Trio
// IconConfigRootWiew.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon B Mårtensson and Robert.
//
// Documentation available under: https://triodocs.org/

import SwiftUI
import Swinject

extension IconConfig {
    struct RootView: BaseView {
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            IconSelection()
                .onAppear(perform: configureView)
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        }
    }
}

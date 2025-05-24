//
// Trio
// MainRootView.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-05-12.
// Most contributions by Ivan Valkou and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            router.view(for: .home)
                .sheet(item: $state.modal) { modal in
                    NavigationView { modal.view }
                        .navigationViewStyle(StackNavigationViewStyle())
                }
                .sheet(item: $state.secondaryModal) { wrapper in
                    wrapper.view
                }

                .onAppear(perform: configureView)
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        }
    }
}

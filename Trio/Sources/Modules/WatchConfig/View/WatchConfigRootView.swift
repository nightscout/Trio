//
// Trio
// WatchConfigRootView.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Pierre L and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import SwiftUI
import Swinject

extension WatchConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Smartwatch Configuration"),
                    content: {
                        NavigationLink("Apple Watch", destination: WatchConfigAppleWatchView(resolver: resolver, state: state))
                        NavigationLink("Garmin", destination: WatchConfigGarminView(state: state))
                    }
                ).listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

//
// Trio
// AlgorithmSettings.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz and tmhastings.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SwiftUI
import Swinject

struct AlgorithmSettings: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Oref Algorithm"),
                content: {
                    Text("Autosens").navigationLink(to: .autosensSettings, from: self)
                    Text("Super Micro Bolus (SMB)").navigationLink(to: .smbSettings, from: self)
                    Text("Dynamic Settings").navigationLink(to: .dynamicISF, from: self)
                    Text("Target Behavior").navigationLink(to: .targetBehavior, from: self)
                    Text("Additionals").navigationLink(to: .algorithmAdvancedSettings, from: self)
                }
            ).listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Algorithm Settings")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

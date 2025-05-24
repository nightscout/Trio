//
// Trio
// DevicesView.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SwiftUI
import Swinject

struct DevicesView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Setup & Configuraton"),
                content: {
                    Text("Insulin Pump").navigationLink(to: .pumpConfig, from: self)
                    Text("Continuous Glucose Monitor").navigationLink(to: .cgm, from: self)
                    Text("Smart Watch").navigationLink(to: .watch, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

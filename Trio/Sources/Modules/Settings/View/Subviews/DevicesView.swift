//
//  FeatureSettingsView.swift
//  Trio
//
//  Created by Deniz Cengiz on 26.07.24.
//
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

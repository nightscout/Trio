//
// Trio
// TherapySettingsView.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-04-06.
// Most contributions by Deniz Cengiz and tmhastings.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SwiftUI
import Swinject

struct TherapySettingsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Basic Settings"),
                content: {
                    Text("Units and Limits").navigationLink(to: .unitsAndLimits, from: self)
                }
            )
            .listRowBackground(Color.chart)

            Section(
                header: Text("Basic Insulin Rates & Targets"),
                content: {
                    Text("Glucose Targets").navigationLink(to: .targetsEditor, from: self)
                    Text("Basal Rates").navigationLink(to: .basalProfileEditor, from: self)
                    Text("Carb Ratios").navigationLink(to: .crEditor, from: self)
                    Text("Insulin Sensitivities").navigationLink(to: .isfEditor, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Therapy Settings")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

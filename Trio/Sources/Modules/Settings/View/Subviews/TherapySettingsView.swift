//
//  FeatureSettingsView.swift
//  Trio
//
//  Created by Deniz Cengiz on 26.07.24.
//
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

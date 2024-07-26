//
//  FeatureSettingsView.swift
//  FreeAPS
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct FeatureSettingsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    var body: some View {
        Form {
            Section(
                header: Text("Oref Algorithm"),
                content: {
                    Text("Preferences (to be omitted").navigationLink(to: .preferencesEditor, from: self)
                    Text("Autosens Settings")
                    Text("Super-Micro-Bolus (SMB) Settings")
                    Text("Dynamic Settings").navigationLink(to: .dynamicISF, from: self)
                }
            ).listRowBackground(Color.chart)

            Section(
                header: Text("Trio Personalization"),
                content: {
                    Text("Bolus Calculator").navigationLink(to: .bolusCalculatorConfig, from: self)
                    Text("Meal Settings").navigationLink(to: .fpuConfig, from: self)
                    Text("Shortcuts").navigationLink(to: .shortcutsConfig, from: self)
                    Text("UI/UX").navigationLink(to: .statisticsConfig, from: self)
                    Text("TODO: Move App Icons into UI/UX 👆")
                    Text("App Icons").navigationLink(to: .iconConfig, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Feature Settings")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

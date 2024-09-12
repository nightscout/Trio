//
//  FeatureSettingsView.swift
//  FreeAPS
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct AlgorithmSettings: BaseView {
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
                    Text("Autosens").navigationLink(to: .autosensSettings, from: self)
                    Text("Super Micro Bolus (SMB)").navigationLink(to: .smbSettings, from: self)
                    Text("Dynamic Sensitivity").navigationLink(to: .dynamicISF, from: self)
                    Text("Target Behavior").navigationLink(to: .targetBehavior, from: self)
                    Text("Additionals").navigationLink(to: .algorithmAdvancedSettings, from: self)
                }
            ).listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Algorithm Settings")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

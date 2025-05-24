//
// Trio
// ServicesView.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import Foundation
import HealthKit
import SwiftUI
import Swinject

struct ServicesView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Connected Services"),
                content: {
                    Text("Nightscout").navigationLink(to: .nighscoutConfig, from: self)
                    Text("Tidepool").navigationLink(to: .tidepoolConfig, from: self)
                    if HKHealthStore.isHealthDataAvailable() {
                        Text("Apple Health").navigationLink(to: .healthkit, from: self)
                    }
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Services")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

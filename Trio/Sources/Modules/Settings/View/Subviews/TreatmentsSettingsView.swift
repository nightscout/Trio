import Foundation
import SwiftUI
import Swinject

struct TreatmentsSettingsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section {
                Text("Bolus Calculator").navigationLink(to: .bolusCalculatorConfig, from: self)
                Text("Quick-Pick Treatments").navigationLink(to: .quickPickTreatmentsConfig, from: self)
                Text("Meal Settings").navigationLink(to: .mealSettings, from: self)
            }
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Treatments")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

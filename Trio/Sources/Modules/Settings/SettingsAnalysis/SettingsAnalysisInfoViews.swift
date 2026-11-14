import SwiftUI

/// Explains the data model.
struct SettingsAnalysisModelsInfoView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            ForEach(SettingsAnalysis.DataModel.allCases) { model in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsAnalysisModelRow(model: model)
                        Text(model.summary)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.strengths, id: \.self) { strength in
                                Label(strength, systemImage: "checkmark")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.chart)
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Data Model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lists every scenario with its description and detection rule.
struct SettingsAnalysisScenariosInfoView: View {
    let units: GlucoseUnits

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            ForEach(SettingsAnalysis.Scenario.allCases) { scenario in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsAnalysisScenarioLabel(scenario: scenario, showsSummary: false)
                            .font(.headline)
                        Text(scenario.summary)
                            .font(.subheadline)
                        Label(scenario.detectionRule(units: units), systemImage: "scope")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.chart)
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Scenarios")
        .navigationBarTitleDisplayMode(.inline)
    }
}

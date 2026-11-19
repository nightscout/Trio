import SwiftUI

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

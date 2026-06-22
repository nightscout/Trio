import SwiftUI

struct AddGlucoseAlertSheet: View {
    @ObservedObject var store: GlucoseAlertsStore
    let onPick: (GlucoseAlertType) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(GlucoseAlertType.allCases) { type in
                        let available = store.availableActiveOptions(forNewAlarmOfType: type)
                        let isAvailable = !available.isEmpty
                        Button {
                            guard isAvailable else { return }
                            onPick(type)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.displayName)
                                        .foregroundColor(.primary)
                                    Text(isAvailable ? type.blurb : unavailableHint(forType: type))
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if isAvailable {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(!isAvailable)
                        .opacity(isAvailable ? 1 : 0.5)
                    }
                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Add Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }

    private func unavailableHint(forType type: GlucoseAlertType) -> String {
        String(localized: "Already set for Day & Night. Delete one of these to add a new one.")
    }
}

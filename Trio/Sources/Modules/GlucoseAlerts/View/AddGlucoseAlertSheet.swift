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
                if !availableTypes.isEmpty {
                    Section(header: Text("Available")) {
                        ForEach(availableTypes) { type in
                            availableRow(for: type)
                        }
                    }.listRowBackground(Color.chart)
                }
                if !unavailableTypes.isEmpty {
                    Section(
                        header: Text("Unavailable"),
                        footer: Text(
                            "Already set for Day & Night. Change the alarm time window to add a second alarm for the same type."
                        )
                    ) {
                        ForEach(unavailableTypes) { type in
                            unavailableRow(for: type)
                        }
                    }.listRowBackground(Color.chart)
                }
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

    private var availableTypes: [GlucoseAlertType] {
        GlucoseAlertType.allCases.filter { !store.availableActiveOptions(forNewAlarmOfType: $0).isEmpty }
    }

    private var unavailableTypes: [GlucoseAlertType] {
        GlucoseAlertType.allCases.filter { store.availableActiveOptions(forNewAlarmOfType: $0).isEmpty }
    }

    private func availableRow(for type: GlucoseAlertType) -> some View {
        Button {
            onPick(type)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .foregroundColor(.primary)
                    Text(type.blurb)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func unavailableRow(for type: GlucoseAlertType) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .foregroundColor(.primary)
                Text(type.blurb)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .opacity(0.5)
    }
}

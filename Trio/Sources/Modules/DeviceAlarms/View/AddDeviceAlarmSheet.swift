import SwiftUI

struct AddDeviceAlarmSheet: View {
    let onPick: (DeviceAlertSeverity) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DeviceAlertSeverity.allCases) { severity in
                        Button {
                            onPick(severity)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: severity))
                                    .foregroundStyle(tint(for: severity))
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(severity.displayName)
                                        .foregroundColor(.primary)
                                    Text(severity.blurb)
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
                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Add Variant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }

    private func icon(for severity: DeviceAlertSeverity) -> String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .timeSensitive: return "bell.badge.fill"
        case .normal: return "bell.fill"
        }
    }

    private func tint(for severity: DeviceAlertSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .timeSensitive: return .orange
        case .normal: return .accentColor
        }
    }
}

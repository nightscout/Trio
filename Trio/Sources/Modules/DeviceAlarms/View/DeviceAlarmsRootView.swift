import SwiftUI
import Swinject

extension DeviceAlarms {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @StateObject private var store = DeviceAlertsStore.shared

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Severity Tiers"),
                    footer: Text(
                        "Three tiers govern every pump and device alarm. Each pump alarm maps to one tier based on how hazardous it is — you configure the tier, not each alarm. See the bottom of this screen for which category lives in which tier."
                    )
                ) {
                    ForEach(DeviceAlertSeverity.allCases) { severity in
                        NavigationLink {
                            DeviceAlarmEditorView(severity: severity, store: store)
                        } label: {
                            row(for: severity)
                        }
                    }
                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Device Alarms")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: configureView)
        }

        @ViewBuilder private func row(for severity: DeviceAlertSeverity) -> some View {
            let config = store.config(for: severity)
            HStack(spacing: 12) {
                Image(systemName: severityIcon(for: severity))
                    .foregroundStyle(severityTint(for: severity))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(severity.displayName)
                        .foregroundColor(.primary)
                    soundSummary(for: config)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }

        private func soundSummary(for config: DeviceAlertSeverityConfig?) -> some View {
            var icon = "speaker.fill"
            var label = String(localized: "Sound on")
            if let config {
                if !config.playsSound {
                    icon = "speaker.slash.fill"
                    label = String(localized: "Sound off")
                } else if config.overridesSilenceAndDND {
                    icon = "speaker.wave.3.fill"
                    label = String(localized: "Overrides Silence & DND")
                }
            }
            return HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }

        private func severityIcon(for severity: DeviceAlertSeverity) -> String {
            switch severity {
            case .critical: return "exclamationmark.triangle.fill"
            case .timeSensitive: return "bell.badge.fill"
            case .normal: return "bell.fill"
            }
        }

        private func severityTint(for severity: DeviceAlertSeverity) -> Color {
            switch severity {
            case .critical: return .red
            case .timeSensitive: return .orange
            case .normal: return .accentColor
            }
        }

        private func categories(for severity: DeviceAlertSeverity) -> [PumpAlertCategory] {
            PumpAlertCategory.allCases.filter { $0.defaultSeverity == severity }
        }
    }
}

import SwiftUI
import Swinject

private enum DeviceAlarmSheet: Identifiable {
    case picker
    case editor(DeviceAlertSeverityConfig, isNew: Bool)

    var id: String {
        switch self {
        case .picker: return "picker"
        case let .editor(config, _): return config.id.uuidString
        }
    }
}

extension DeviceAlarms {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @StateObject private var store = DeviceAlertsStore.shared

        @State private var sheet: DeviceAlarmSheet?
        @State private var pendingNewSeverity: DeviceAlertSeverity?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                ForEach(DeviceAlertSeverity.allCases) { severity in
                    Section(
                        header: header(for: severity),
                        footer: footer(for: severity)
                    ) {
                        ForEach(store.configs(in: severity)) { config in
                            row(for: config)
                                .opacity(config.isEnabled ? 1 : 0.5)
                        }
                    }.listRowBackground(Color.chart)
                }

                Section {
                    Text("Day & Night Windows")
                        .navigationLink(to: .alarmWindows, from: self)
                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Pump & CGM Alarms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .picker } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $sheet, onDismiss: handleSheetDismiss) { which in
                switch which {
                case .picker:
                    AddDeviceAlarmSheet { severity in
                        pendingNewSeverity = severity
                        sheet = nil
                    }
                case let .editor(config, isNew):
                    DeviceAlarmEditorView(
                        store: store,
                        initial: config,
                        isNew: isNew,
                        onDone: { sheet = nil },
                        onCancel: { sheet = nil }
                    )
                }
            }
            .onAppear(perform: configureView)
        }

        private func handleSheetDismiss() {
            guard let severity = pendingNewSeverity else { return }
            pendingNewSeverity = nil
            DispatchQueue.main.async {
                let new = DeviceAlertSeverityConfig(
                    severity: severity,
                    activeOption: nextAvailableOption(for: severity)
                )
                sheet = .editor(new, isNew: true)
            }
        }

        // MARK: - Section header / footer

        private func header(for severity: DeviceAlertSeverity) -> some View {
            HStack {
                Image(systemName: severityIcon(for: severity))
                    .foregroundStyle(severityTint(for: severity))
                Text(severity.displayName)
            }
        }

        private func footer(for severity: DeviceAlertSeverity) -> some View {
            Text(severity.blurb)
        }

        // MARK: - Row

        @ViewBuilder private func row(for config: DeviceAlertSeverityConfig) -> some View {
            Button {
                sheet = .editor(config, isNew: false)
            } label: {
                HStack(spacing: 12) {
                    AlarmWindowIcon(option: config.activeOption)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(windowLabel(for: config.activeOption))
                            .foregroundColor(.primary)
                        soundSummary(for: config)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if store.canDelete(config) {
                    Button(role: .destructive) {
                        store.remove(config)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }

        private func soundSummary(for config: DeviceAlertSeverityConfig) -> some View {
            let icon: String
            let label: String
            if !config.playsSound {
                icon = "speaker.slash.fill"
                label = String(localized: "Sound off")
            } else if config.overridesSilenceAndDND {
                icon = "speaker.wave.3.fill"
                label =
                    "\(AlarmSoundCatalog.displayName(for: config.soundFilename)) • \(String(localized: "Overrides Silence & Focus Mode"))"
            } else {
                icon = "speaker.fill"
                label = AlarmSoundCatalog.displayName(for: config.soundFilename)
            }
            return HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }

        // MARK: - Helpers

        private func windowLabel(for option: ActiveOption) -> String {
            switch option {
            case .always: return String(localized: "Day & Night")
            case .day: return String(localized: "Day only")
            case .night: return String(localized: "Night only")
            }
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

        /// Suggest an `ActiveOption` not yet used in this severity tier so the
        /// editor opens on a meaningful new variant instead of duplicating
        /// the existing `.always` row.
        private func nextAvailableOption(for severity: DeviceAlertSeverity) -> ActiveOption {
            let used = Set(store.configs(in: severity).map(\.activeOption))
            for candidate in [ActiveOption.day, .night, .always] where !used.contains(candidate) {
                return candidate
            }
            return .day
        }
    }
}

import SwiftUI
import Swinject

private enum DeviceAlarmSheet: Identifiable {
    case picker
    case editor(DeviceAlertSeverityConfig, isNew: Bool)
    case help(DeviceAlertSeverity)

    var id: String {
        switch self {
        case .picker: return "picker"
        case let .editor(config, _): return config.id.uuidString
        case let .help(severity): return "helpSheet_" + severity.id
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

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                ForEach(DeviceAlertSeverity.allCases) { severity in
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: severityIcon(for: severity))
                                    .foregroundStyle(severityTint(for: severity))
                                Text(severity.displayName)
                                Spacer()
                            }.font(.headline)

                            HStack(alignment: .center) {
                                Text(severity.blurb)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button(action: {
                                    sheet = .help(severity)
                                }) {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }.padding(.vertical, 5)
                        }

                        ForEach(store.configs(in: severity)) { config in
                            row(for: config)
                                .opacity(config.isEnabled ? 1 : 0.5)
                        }
                    }.listRowBackground(Color.chart)
                }

                Section {
                    Text("Day & Night Windows")
                        .foregroundStyle(Color.accentColor)
                        .navigationLink(to: .alarmWindows, from: self)
                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Device Alarms")
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
                case let .help(severity):
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: Binding(
                            get: { sheet != nil },
                            set: { if !$0 { sheet = nil } }
                        ),
                        hintLabel: String(
                            localized: "\(severity.displayName) Device Alerts",
                            comment: "Device Alerts help sheet label; text reads: '<severity level> Device Alerts'."
                        ),
                        hintText: selectedVerboseHint ?? AnyView(
                            VStack(alignment: .leading, spacing: 10) {
                                Text(severity.hintText)
                            }
                        ),
                        sheetTitle: String(localized: "Help", comment: "Help sheet title")
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
            // Show the sound and override facts independently. Previously
            // the override badge was hidden when sound was off, but "sound
            // off + override on" is a valid combo (silent + haptic that
            // breaks through Focus / Sleep) and the user needs to see it.
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: config.playsSound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    Text(config.playsSound ? "Sound on" : "Sound off")
                }
                if config.overridesSilenceAndDND {
                    Text("·")
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge.fill")
                        Text("Overrides Focus")
                    }
                }
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

import SwiftUI
import Swinject

private enum AlertSheet: Identifiable {
    case picker
    case editor(GlucoseAlert, isNew: Bool)

    var id: String {
        switch self {
        case .picker: return "picker"
        case let .editor(alert, _): return alert.id.uuidString
        }
    }
}

extension GlucoseAlerts {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @StateObject private var store = GlucoseAlertsStore.shared

        @State private var sheet: AlertSheet?
        @State private var pendingNewType: GlucoseAlertType?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var displayPickerLowGlucose: Bool = false
        @State private var displayPickerHighGlucose: Bool = false

        var body: some View {
            List {
                if !enabledAlerts.isEmpty {
                    Section(header: Text("Enabled")) {
                        ForEach(enabledAlerts) { alarm in
                            row(for: alarm)
                        }
                    }.listRowBackground(Color.chart)
                }
                if !disabledAlerts.isEmpty {
                    Section(header: Text("Disabled")) {
                        ForEach(disabledAlerts) { alarm in
                            row(for: alarm).opacity(0.6)
                        }
                    }.listRowBackground(Color.chart)
                }

                // FIXME: make this into a nice setting with mini and verbose hint
                Section {
                    Text("Day & Night Windows")
                        .navigationLink(to: .alarmWindows, from: self)
                }.listRowBackground(Color.chart)

                Section(footer: Text(
                    "On by default for all CGM or apps that handle glucose alerts (all Dexcom CGMs, xDrip4iOS). Turn off if you've disabled those and want Trio to alert you instead."
                )) {
                    Toggle(isOn: Binding(
                        get: { !store.configuration.forceTrioAlertsWhenCGMProvidesOwn },
                        set: { store.configuration.forceTrioAlertsWhenCGMProvidesOwn = !$0 }
                    )) {
                        Text("Use CGM App Alerts")
                    }
                }.listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.glucoseBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show Glucose App Badge")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Show Glucose App Badge"),
                    miniHint: String(localized: "Show your current glucose on Trio app icon."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "This will add your current glucose on the top right of your Trio icon as a red notification badge. Changing setting takes effect on next Glucose reading."
                        )
                    },
                    headerText: String(localized: "Glucose App Badge")
                )
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Glucose Alarms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .picker } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $sheet, onDismiss: handleSheetDismiss) { which in
                switch which {
                case .picker:
                    AddGlucoseAlertSheet { type in
                        pendingNewType = type
                        sheet = nil
                    }
                case let .editor(alarm, isNew):
                    GlucoseAlertEditorView(
                        store: store,
                        initial: alarm,
                        isNew: isNew,
                        units: state.units,
                        onDone: { sheet = nil },
                        onCancel: { sheet = nil }
                    )
                }
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .onAppear(perform: configureView)
        }

        private func handleSheetDismiss() {
            guard let type = pendingNewType else { return }
            pendingNewType = nil
            DispatchQueue.main.async {
                sheet = .editor(GlucoseAlert(type: type), isNew: true)
            }
        }

        // MARK: - Sorted lists

        private var enabledAlerts: [GlucoseAlert] {
            store.alerts
                .filter(\.isEnabled)
                .sorted { lhs, rhs in
                    lhs.type.priority < rhs.type.priority
                }
        }

        private var disabledAlerts: [GlucoseAlert] {
            store.alerts
                .filter { !$0.isEnabled }
                .sorted { lhs, rhs in
                    lhs.type.priority < rhs.type.priority
                }
        }

        // MARK: - Row

        @ViewBuilder private func row(for alarm: GlucoseAlert) -> some View {
            Button {
                sheet = .editor(alarm, isNew: false)
            } label: {
                HStack(spacing: 12) {
                    AlarmWindowIcon(option: alarm.activeOption)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alarm.name)
                            .foregroundColor(.primary)
                        Text(summary(for: alarm))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        soundSummary(for: alarm)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if store.canDelete(alarm) {
                    Button(role: .destructive) {
                        store.remove(alarm)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }

        private func summary(for alarm: GlucoseAlert) -> String {
            let comparator: String = {
                switch alarm.type {
                case .high: return String(localized: "above")
                default: return String(localized: "below")
                }
            }()
            let threshold = "\(alarm.thresholdMgDL.formatted(for: state.units)) \(state.units.rawValue)"
            let window = AlarmEnumDescription.description(for: alarm.activeOption)
            return "\(comparator.localizedCapitalized) \(threshold) • \(window)"
        }

        private func soundSummary(for alarm: GlucoseAlert) -> some View {
            var icon = "speaker.fill"
            var label = String(localized: "Sound on")
            if !alarm.playsSound {
                icon = "speaker.slash.fill"
                label = String(localized: "Sound off")
            } else if alarm.overridesSilenceAndDND {
                icon = "speaker.wave.3.fill"
                label = String(localized: "Override Silence & Focus")
            }
            return HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
    }
}

private enum AlarmEnumDescription {
    static func description(for option: ActiveOption) -> String {
        switch option {
        case .always: return String(localized: "Day & Night")
        case .day: return String(localized: "Day only")
        case .night: return String(localized: "Night only")
        }
    }
}

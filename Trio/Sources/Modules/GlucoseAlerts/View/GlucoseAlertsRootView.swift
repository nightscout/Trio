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
                if !cgmHandledAlerts.isEmpty {
                    Section(
                        header: Text("Handled by CGM App"),
                        footer: cgmHandledFooter
                    ) {
                        ForEach(cgmHandledAlerts) { alarm in
                            row(for: alarm).opacity(0.6)
                        }
                    }.listRowBackground(Color.chart)
                }

                // FIXME: make this into a nice setting with mini and verbose hint
                Section {
                    Text("Day & Night Windows")
                        .foregroundStyle(Color.accentColor)
                        .navigationLink(to: .alarmWindows, from: self)
                }.listRowBackground(Color.chart)

                Section(footer: Text(useCGMAlertsFooter)) {
                    Toggle(isOn: Binding(
                        // When the active CGM has no companion app to defer
                        // to, force the visible state OFF regardless of the
                        // stored preference — there's nothing for the toggle
                        // to control, so showing it ON would mislead.
                        get: {
                            guard state.cgmProvidesOwnAlerts else { return false }
                            return !store.configuration.forceTrioAlertsWhenCGMProvidesOwn
                        },
                        set: { store.configuration.forceTrioAlertsWhenCGMProvidesOwn = !$0 }
                    )) {
                        Text("Use CGM App Alerts")
                    }
                    .disabled(!state.cgmProvidesOwnAlerts)
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
                    AddGlucoseAlertSheet(store: store) { type in
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
            .onAppear {
                configureView()
                state.refreshCGMOwnership()
            }
        }

        private func handleSheetDismiss() {
            guard let type = pendingNewType else { return }
            pendingNewType = nil
            DispatchQueue.main.async {
                var seed = GlucoseAlert(type: type)
                // Default new alarm to the first available window so it
                // doesn't overlap with whatever is already configured.
                let available = store.availableActiveOptions(forNewAlarmOfType: type)
                if let first = ActiveOption.allCases.first(where: available.contains) {
                    seed.activeOption = first
                }
                sheet = .editor(seed, isNew: true)
            }
        }

        // MARK: - Sorted lists

        /// Mirror of `GlucoseAlertCoordinator.shouldRespect(alarm:)`'s
        /// CGM-ownership branch: when "Use CGM App Alerts" is ON and the
        /// active CGM provides its own glucose alerts, the coordinator
        /// silences reading-driven types. The view surfaces this by moving
        /// those alarms into a dedicated section.
        private var isCGMSuppressionActive: Bool {
            !store.configuration.forceTrioAlertsWhenCGMProvidesOwn && state.cgmProvidesOwnAlerts
        }

        private var cgmHandledAlerts: [GlucoseAlert] {
            guard isCGMSuppressionActive else { return [] }
            return store.alerts
                .filter { $0.isEnabled && $0.type.isReadingDriven }
                .sorted { lhs, rhs in
                    lhs.type.priority < rhs.type.priority
                }
        }

        /// Footer for the "Use CGM App Alerts" toggle. Names the eligible
        /// CGMs when one of them is active and the user can decide; when
        /// the active CGM has no companion app the toggle is disabled and
        /// the footer says Trio is handling alarms.
        private var useCGMAlertsFooter: String {
            if state.cgmProvidesOwnAlerts {
                return String(
                    localized:
                    "Your CGM app handles alerts (Dexcom G6 / One, G7 / One+, or xDrip4iOS). Turn off to let Trio alert you."
                )
            }
            return String(
                localized:
                "Your CGM has no companion app, so Trio handles alarms."
            )
        }

        /// Footer for the "Handled by CGM App" section. Names the specific
        /// companion app, and renders its name as a deep link when a URL
        /// scheme is known for that app (see CGMManagerAlertOwnership).
        @ViewBuilder private var cgmHandledFooter: some View {
            if let info = state.cgmAppInfo {
                Text(handledFooterMarkdown(for: info))
            } else {
                Text(
                    "These alarms are silenced because the CGM app handles them. To have Trio notify you instead, turn off \"Use CGM App Alerts\" below."
                )
            }
        }

        private func handledFooterMarkdown(for info: CGMManagerAlertOwnership.OwningApp) -> AttributedString {
            let body = String(
                format: String(
                    localized:
                    "These alarms are silenced because the %@ app handles CGM alerts. To have Trio notify you instead, turn off \"Use CGM App Alerts\" below."
                ),
                "{{NAME}}"
            )
            var result = AttributedString(body)
            if let range = result.range(of: "{{NAME}}") {
                var name = AttributedString(info.name)
                if let url = info.deepLink {
                    name.link = url
                }
                result.replaceSubrange(range, with: name)
            }
            return result
        }

        private var enabledAlerts: [GlucoseAlert] {
            let handled = Set(cgmHandledAlerts.map(\.id))
            return store.alerts
                .filter(\.isEnabled)
                .filter { !handled.contains($0.id) }
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
                case .carbsRequired: return String(localized: "at least")
                default: return String(localized: "below")
                }
            }()
            let threshold: String = {
                // `thresholdMgDL` stores grams for carbsRequired — no
                // mg/dL ↔ mmol/L conversion and a fixed "g" unit label.
                if alarm.type == .carbsRequired {
                    return "\(alarm.thresholdMgDL) \(String(localized: "g", comment: "gram of carbs"))"
                }
                return "\(alarm.thresholdMgDL.formatted(for: state.units)) \(state.units.rawValue)"
            }()
            let window = AlarmEnumDescription.description(for: alarm.activeOption)
            return "\(comparator.localizedCapitalized) \(threshold) • \(window)"
        }

        private func soundSummary(for alarm: GlucoseAlert) -> some View {
            // Show the sound and override facts independently. Previously
            // the override badge was hidden when sound was off, but "sound
            // off + override on" is a valid combo (silent + haptic that
            // breaks through Focus / Sleep) and the user needs to see it.
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: alarm.playsSound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    Text(alarm.playsSound ? "Sound on" : "Sound off")
                }
                if alarm.overridesSilenceAndDND {
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

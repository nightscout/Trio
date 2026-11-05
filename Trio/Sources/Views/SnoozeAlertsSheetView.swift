import SwiftUI
import Swinject

/// Shared "Snooze All" sheet. Used from Notifications settings and the home
/// glucose long-press. Wraps `TrioAlertManager.applySnooze` directly — no
/// router / module hop.
struct SnoozeAlertsSheetView: View {
    let resolver: Resolver
    @Binding var isPresented: Bool

    @State private var snoozeUntilDate: Date = .distantPast
    @State private var units: GlucoseUnits = .mgdL

    @ObservedObject private var alertsStore = GlucoseAlertsStore.shared
    @AppStorage("SnoozeAlertsSheetView.thresholdsExpanded") private var thresholdsExpanded = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        NavigationStack {
            List {
                if snoozeUntilDate > Date() {
                    Section {
                        HStack {
                            Image(systemName: "moon.zzz.fill").foregroundStyle(.tint)
                            Text(String(
                                format: String(localized: "Snoozed until %@"),
                                snoozeUntilDate.formatted(date: .omitted, time: .shortened)
                            ))
                                .font(.headline)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            endSnoozeAction
                        }
                        .listRowBackground(Color.chart)
                    } footer: {
                        HStack {
                            Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                            Text("Swipe left to end snooze.")
                        }
                    }
                }
                Section(footer: Text(
                    "Pick a duration to mute every Trio alarm. Critical alerts (e.g. occlusion, urgent low) still pierce the snooze."
                )) {
                    ForEach(NotificationResponseAction.allCases, id: \.self) { action in
                        Button {
                            applySnooze(action.duration)
                        } label: {
                            HStack {
                                Text(action.localizedTitle).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.footnote)
                            }
                        }
                    }
                }.listRowBackground(Color.chart)

                activeAlarmThresholdSection
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Snooze Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { isPresented = false }
                }
            }
            .onAppear {
                snoozeUntilDate = UserDefaults.standard
                    .object(forKey: "UserNotificationsManager.snoozeUntilDate") as? Date ?? .distantPast
                units = resolver.resolve(SettingsManager.self)?.settings.units ?? .mgdL
            }
        }
    }

    // MARK: - Active alarm thresholds

    /// Shows the current active alarms for the configured time window. Urgent-low is excluded.
    private var activeAlarms: [GlucoseAlert] {
        let isNight = alertsStore.configuration.isNight(at: Date())
        return alertsStore.alerts
            .filter { alert in
                guard alert.type != .urgentLow, alert.shouldEvaluate else { return false }
                switch alert.activeOption {
                case .always: return true
                case .day: return !isNight
                case .night: return isNight
                }
            }
            .sorted { $0.type.priority < $1.type.priority }
    }

    @ViewBuilder private var activeAlarmThresholdSection: some View {
        if !activeAlarms.isEmpty {
            Section(footer: activeAlarmThresholdFooter) {
                DisclosureGroup(isExpanded: $thresholdsExpanded) {
                    ForEach(activeAlarms) { alert in
                        activeAlarmRow(alert)
                    }
                } label: {
                    Label("Active Alarm Thresholds", systemImage: "slider.horizontal.3")
                }
            }.listRowBackground(Color.chart)
        }
    }

    @ViewBuilder private var activeAlarmThresholdFooter: some View {
        if thresholdsExpanded {
            Text(
                "Quickly move the thresholds of the alarms active in the current day/night window. Changes apply immediately and stay until you change them back."
            )
        }
    }

    @ViewBuilder private func activeAlarmRow(_ alert: GlucoseAlert) -> some View {
        let range = alert.type.thresholdRange
        let lowerBound = NSDecimalNumber(decimal: range.lowerBound).doubleValue
        let upperBound = NSDecimalNumber(decimal: range.upperBound).doubleValue

        VStack(spacing: 4) {
            HStack {
                AlarmWindowIcon(option: alert.activeOption)
                    .font(.footnote)
                Text(alert.name)
                Spacer()
                Text(formattedThreshold(alert.thresholdMgDL, type: alert.type))
                    .fontWeight(.bold).fontDesign(.rounded)
            }
            Slider(
                value: thresholdBinding(for: alert.id),
                in: lowerBound ... upperBound,
                step: 5
            ) {
                Text(alert.name)
            } minimumValueLabel: {
                Text(formattedThreshold(range.lowerBound, type: alert.type))
                    .font(.footnote).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(formattedThreshold(range.upperBound, type: alert.type))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text(alert.name))
            .accessibilityValue(Text(formattedThreshold(alert.thresholdMgDL, type: alert.type)))
        }
    }

    private func thresholdBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let alert = alertsStore.alerts.first(where: { $0.id == id }) else { return 0 }
                return NSDecimalNumber(decimal: alert.thresholdMgDL).doubleValue
            },
            set: { newValue in
                guard let index = alertsStore.alerts.firstIndex(where: { $0.id == id }) else { return }
                alertsStore.alerts[index].thresholdMgDL = Decimal(Int(newValue.rounded()))
            }
        )
    }

    private func formattedThreshold(_ value: Decimal, type: GlucoseAlertType) -> String {
        type == .carbsRequired
            ? value.description + " " + String(localized: "g", comment: "gram unit")
            : value.formatted(for: units) + " " + units.rawValue
    }

    private var endSnoozeAction: some View {
        Button(role: .destructive) {
            endSnooze()
        } label: {
            Label("End Snooze", systemImage: "alarm.waves.left.and.right.fill")
        }
        .tint(.red)
    }

    private func applySnooze(_ duration: TimeInterval) {
        let trioAlertManager = resolver.resolve(TrioAlertManager.self)
        Task { @MainActor in
            await trioAlertManager?.applySnooze(for: duration)
            snoozeUntilDate = Date().addingTimeInterval(duration)
            isPresented = false
        }
    }

    private func endSnooze() {
        let trioAlertManager = resolver.resolve(TrioAlertManager.self)
        Task { @MainActor in
            await trioAlertManager?.applySnooze(for: 0)
            snoozeUntilDate = Date().addingTimeInterval(0)
        }
    }
}

import SwiftUI

struct AlarmSnoozeView: View {
    let state: WatchState

    @State private var showingSnoozeOptions = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let isSnoozed = state.snoozeUntilDate > context.date
            let remainingMinutes = max(Int(ceil(state.snoozeUntilDate.timeIntervalSince(context.date) / 60)), 0)

            VStack(spacing: 8) {
                Button {
                    showingSnoozeOptions = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: isSnoozed ? "bell.slash.fill" : "bell.fill")
                            .font(.title2)
                        if isSnoozed {
                            Text("\(remainingMinutes) m")
                                .font(.headline).fontWeight(.bold).fontDesign(.rounded)
                        }
                    }
                    .foregroundStyle(isSnoozed ? Color.secondary : Color.primary)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.4), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)

                Text(
                    isSnoozed
                        ? String(
                            format: String(localized: "Snoozed until %@"),
                            state.snoozeUntilDate.formatted(date: .omitted, time: .shortened)
                        )
                        : String(localized: "Alarms active")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Alarms"))
            .accessibilityValue(Text(
                isSnoozed
                    ? String(
                        format: String(localized: "snoozed, %d minutes remaining", comment: "Accessibility: alarm snooze"),
                        remainingMinutes
                    )
                    : String(localized: "active", comment: "Accessibility: alarms active")
            ))
            .accessibilityHint(Text(String(localized: "Opens snooze options", comment: "Accessibility hint")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showingSnoozeOptions = true }
        }
        .sheet(isPresented: $showingSnoozeOptions) {
            AlarmSnoozeOptionsView(state: state) {
                showingSnoozeOptions = false
            }
        }
    }
}

struct AlarmSnoozeOptionsView: View {
    let state: WatchState
    var onDismiss: () -> Void

    var body: some View {
        NavigationView {
            List {
                if state.snoozeUntilDate > Date() {
                    Button {
                        state.sendSnoozeRequest(minutes: 0)
                        onDismiss()
                    } label: {
                        Label("End Snooze", systemImage: "alarm.waves.left.and.right.fill")
                    }
                    .foregroundColor(.white)
                    .listRowBackground(
                        Color.loopRed
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                }

                ForEach(NotificationResponseAction.allCases, id: \.self) { action in
                    Button(action.localizedTitle) {
                        state.sendSnoozeRequest(minutes: action.minutes)
                        onDismiss()
                    }
                }
            }
            .navigationTitle("Snooze Alerts")
        }
    }
}

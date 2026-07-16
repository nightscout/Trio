import Foundation
import SwiftUI

// MARK: - Zone C: meal panel (IOB / COB / delivery rate)

extension Home.RootView {
    @ViewBuilder func mealPanel() -> some View {
        HStack {
            HStack {
                Image(systemName: "syringe.fill")
                    .font(.callout)
                    .foregroundColor(Color.insulin)
                Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits
                            .string(from: state.currentIOB as NSNumber) ?? "0"
                    ) +
                        String(localized: " U", comment: "Insulin unit")
                )
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            }

            Spacer()

            HStack {
                Image(systemName: "fork.knife")
                    .font(.callout)
                    .foregroundColor(.loopYellow)
                Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits.string(
                            from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                        ) ?? "0"
                    ) +
                        String(localized: " g", comment: "gram of carbs")
                )
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            }

            Spacer()

            alarmsPill
        }.padding(.horizontal)
    }

    func refreshAlarmsSnooze() {
        alarmsSnoozeUntil = UserDefaults.standard
            .object(forKey: "UserNotificationsManager.snoozeUntilDate") as? Date ?? .distantPast
    }

    /// Bell pill matching the header pills; countdown replaces the label while snoozed.
    @ViewBuilder var alarmsPill: some View {
        // timerDate keeps the countdown ticking
        let isSnoozed = alarmsSnoozeUntil > state.timerDate
        let remainingMinutes = max(Int(ceil(alarmsSnoozeUntil.timeIntervalSince(state.timerDate) / 60)), 0)

        Button {
            showSnoozeSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isSnoozed ? "bell.slash.fill" : "bell.fill")
                    .font(.callout)
                Text(isSnoozed ? "\(remainingMinutes) m" : String(localized: "Alarms", comment: "Alarms header item"))
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .foregroundStyle(isSnoozed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.4), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Persistent banner shown at the top of the home screen when an alarm is active.
/// Provides Snooze and Acknowledge buttons so the user can always dismiss the alarm.
struct AlarmBannerView: View {
    @ObservedObject private var alarmSound = AlarmSound.shared

    @State private var showSnoozeOptions = false

    private let snoozeDurations: [(label: String, interval: TimeInterval)] = [
        ("20 min", 20 * 60),
        ("1 hr", 60 * 60),
        ("3 hr", 3 * 60 * 60),
        ("6 hr", 6 * 60 * 60)
    ]

    var body: some View {
        if alarmSound.isAlarmActive {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text(String(localized: "Loop Failure Alarm Active", comment: "Loop failure alarm banner title"))
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Spacer()
                }

                if showSnoozeOptions {
                    HStack(spacing: 8) {
                        ForEach(snoozeDurations, id: \.interval) { duration in
                            Button {
                                alarmSound.snooze(for: duration.interval)
                                showSnoozeOptions = false
                            } label: {
                                Text(duration.label)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.25))
                                    .cornerRadius(6)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Button {
                            showSnoozeOptions = true
                        } label: {
                            Label(
                                String(localized: "Snooze", comment: "Snooze alarm button"),
                                systemImage: "moon.zzz.fill"
                            )
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.25))
                            .cornerRadius(8)
                        }

                        Button {
                            alarmSound.acknowledge()
                        } label: {
                            Label(
                                String(localized: "Acknowledge", comment: "Acknowledge alarm button"),
                                systemImage: "bell.slash.fill"
                            )
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.25))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
            .background(Color.red)
            .cornerRadius(12)
            .shadow(radius: 4)
            .padding(.horizontal)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut, value: alarmSound.isAlarmActive)
        }
    }
}

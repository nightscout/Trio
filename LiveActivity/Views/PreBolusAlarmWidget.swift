import ActivityKit
import SwiftUI
import WidgetKit

#if canImport(AlarmKit)
    import AlarmKit

    /// Renders the pre-bolus countdown on the Lock Screen and in the Dynamic Island, driven by an
    /// AlarmKit `AlarmAttributes<PreBolusAlarmMetadata>` alarm.
    @available(iOS 26.0, *) struct PreBolusAlarmWidget: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: AlarmAttributes<PreBolusAlarmMetadata>.self) { context in
                PreBolusAlarmLockScreenView(context: context)
                    .padding()
                    .activityBackgroundTint(Color.black.opacity(0.55))
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(context.attributes.tintColor)
                            .font(.title2)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        PreBolusCountdownText(context: context)
                            .font(.title2.monospacedDigit())
                            .foregroundStyle(context.attributes.tintColor)
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        Text(context.mealSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } compactLeading: {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(context.attributes.tintColor)
                } compactTrailing: {
                    PreBolusCountdownText(context: context)
                        .monospacedDigit()
                        .foregroundStyle(context.attributes.tintColor)
                } minimal: {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(context.attributes.tintColor)
                }
                .keylineTint(context.attributes.tintColor)
            }
        }
    }

    // MARK: - Lock Screen

    @available(iOS 26.0, *) private struct PreBolusAlarmLockScreenView: View {
        let context: ActivityViewContext<AlarmAttributes<PreBolusAlarmMetadata>>

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.title)
                    .foregroundStyle(context.attributes.tintColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.isAlerting ? "Time to eat" : "Pre-bolus")
                        .font(.headline)

                    if !context.mealSummary.isEmpty {
                        Text(context.mealSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                PreBolusCountdownText(context: context)
                    .font(.title.monospacedDigit())
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    // MARK: - Countdown

    @available(iOS 26.0, *) private struct PreBolusCountdownText: View {
        let context: ActivityViewContext<AlarmAttributes<PreBolusAlarmMetadata>>

        var body: some View {
            switch context.state.mode {
            case let .countdown(countdown):
                // A late render can arrive after the fire date; `max` keeps the range valid.
                Text(timerInterval: Date.now ... max(Date.now, countdown.fireDate), countsDown: true)
                    .multilineTextAlignment(.trailing)
            case .paused:
                Text("Paused")
            case .alert:
                Text("Now")
            }
        }
    }

    // MARK: - Helpers

    @available(iOS 26.0, *)
    private extension ActivityViewContext<AlarmAttributes<PreBolusAlarmMetadata>> {
        var isAlerting: Bool {
            if case .alert = state.mode { return true }
            return false
        }

        /// "45 g · 2.4 U", omitting either half when it is zero.
        var mealSummary: String {
            guard let metadata = attributes.metadata else { return "" }

            var parts: [String] = []
            if metadata.carbs > 0 {
                parts.append(String(
                    localized: "\(Int(metadata.carbs.rounded())) g",
                    comment: "Carb amount in grams in the pre-bolus Live Activity"
                ))
            }
            if metadata.bolusAmount > 0 {
                parts.append(String(
                    localized: "\(metadata.bolusAmount, specifier: "%.2f") U",
                    comment: "Insulin amount in units in the pre-bolus Live Activity"
                ))
            }
            return parts.joined(separator: " · ")
        }
    }
#endif

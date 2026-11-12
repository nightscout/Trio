import SwiftUI

struct GlucoseTrendView: View {
    let state: WatchState
    let rotationDegrees: Double
    let isWatchStateDated: Bool
    /// What needs doing, or why the watch's link brings no readings: in place of the ages under the bubble.
    let sensorStateText: String?
    /// The phone's last update is older than two loop cycles, so its loop time is no longer known.
    let isPhoneStateDated: Bool
    /// Ticks the reading's and the loop's age.
    let now: Date

    private var isReadingDirectly: Bool { WatchCGMHost.shared.isReadingDirectly }

    /// Minutes since the phone's last loop. Reading directly, the watch ages the loop's date itself and shows none
    /// once the phone has gone quiet; otherwise the phone's text as sent.
    private var loopMinutes: Int? {
        guard isReadingDirectly else {
            return state.lastLoopTime?.split(separator: " ").first.flatMap { Int($0) }
        }
        guard !isPhoneStateDated, let lastLoopDate = state.lastLoopDate else { return nil }
        return Int((now.timeIntervalSince(lastLoopDate) - 30) / 60) + 1
    }

    /// The loop's status: green up to 5 minutes, yellow up to 10, red after; grey when not known.
    private var loopColor: Color {
        guard let minutes = loopMinutes, !isWatchStateDated else { return Color.secondary }
        switch minutes {
        case ...5:
            return Color.loopGreen
        case 6 ... 10:
            return Color.loopYellow
        default:
            return Color.loopRed
        }
    }

    var circleSize: CGFloat {
        switch state.deviceType {
        case .watch40mm:
            return 82
        case .watch41mm,
             .watch42mm:
            return 86
        case .watch44mm:
            return 96
        case .unknown,
             .watch45mm:
            return 103
        case .watch49mm:
            return 105
        }
    }

    var lineWidth: CGFloat {
        switch state.deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm,
             .watch44mm:
            return 1
        case .unknown,
             .watch45mm:
            return 1.5
        case .watch49mm:
            return 1.5
        }
    }

    var shadowRadius: CGFloat {
        switch state.deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 8
        case .watch44mm:
            return 9
        case .unknown,
             .watch45mm:
            return 12
        case .watch49mm:
            return 12
        }
    }

    var currentGlucoseFontSize: Font {
        switch state.deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm,
             .watch44mm:
            return .title2
        case .unknown,
             .watch45mm:
            return .title
        case .watch49mm:
            return .title
        }
    }

    var minutesAgoFontSize: CGFloat {
        switch state.deviceType {
        case .watch40mm,
             .watch41mm:
            return 9
        case .unknown,
             .watch42mm,
             .watch44mm:
            return 10
        case .watch45mm:
            return 11
        case .watch49mm:
            return 10
        }
    }

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(loopColor, lineWidth: lineWidth)
                    .frame(width: circleSize, height: circleSize)
                    .background(Circle().fill(Color.bgDarkBlue))
                    .shadow(color: loopColor, radius: shadowRadius)

                TrendShape(
                    isWatchStateDated: isWatchStateDated,
                    rotationDegrees: rotationDegrees,
                    deviceType: state.deviceType
                )
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)
                .shadow(color: Color.black.opacity(0.5), radius: 5)

                VStack(alignment: .center) {
                    Text(isWatchStateDated ? "--" : state.currentGlucose)
                        .fontWeight(.semibold)
                        .font(currentGlucoseFontSize)
                        .foregroundStyle(isWatchStateDated ? Color.secondary : state.currentGlucoseColorString.toColor())

                    if let delta = state.delta {
                        Text(isWatchStateDated ? "--" : delta)
                            .fontWeight(.semibold)
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isReadingDirectly {
                directReadingStatus
            } else {
                Text(
                    isWatchStateDated ?
                        String(localized: "STALE DATA", comment: "Information displayed when watch app data outdated or stale.") :
                        state
                        .lastLoopTime ?? "--"
                )
                .font(.system(size: minutesAgoFontSize))
                .fontWidth(isWatchStateDated ? .expanded : .standard)
            }

            Spacer()

        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Reading directly, one line: the reading's age, with the loop's only once it is late and otherwise the sensor's
    /// note (the grace period); what needs doing (pairing, a code, the warmup's countdown) in place of both.
    private var directReadingStatus: some View {
        Group {
            if let actionText {
                Text(actionText).foregroundStyle(WatchCGMHost.shared.sensorHasEnded ? Color.loopRed : .yellow)
            } else if isWatchStateDated {
                Text(String(localized: "STALE DATA", comment: "Information displayed when watch app data outdated or stale."))
                    .fontWidth(.expanded)
            } else if let readingDate = state.glucoseValues.last?.date {
                let readingMinutes = max(0, Int(now.timeIntervalSince(readingDate) / 60))
                Text(String(localized: "\(readingMinutes) min", comment: "Watch: age of the shown glucose reading")) + ageSuffix
            }
        }
        .font(.system(size: minutesAgoFontSize))
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }

    /// The warmup's minutes left while it counts down, else the sensor's state text.
    private var actionText: String? {
        if let warmupEndsAt = WatchCGMHost.shared.warmupEndsAt {
            let minutesLeft = Int((warmupEndsAt.timeIntervalSince(now) / 60).rounded(.up))
            if minutesLeft > 0 {
                return String(localized: "Warmup \(minutesLeft) min", comment: "Watch: minutes left of the sensor's warmup")
            }
        }
        return sensorStateText
    }

    /// The loop's age once it is late or not known (the ring's green says it is on time), else the sensor's note.
    private var ageSuffix: Text {
        let separator = Text(verbatim: " · ").foregroundStyle(.secondary)
        if (loopMinutes ?? .max) > 5 {
            let loopText = loopMinutes
                .map { String(localized: "Loop \($0) min", comment: "Watch: minutes since the phone's last loop") } ??
                String(localized: "Loop –", comment: "Watch: the phone's last loop is not known")
            return separator + Text(loopText).foregroundStyle(loopColor)
        }
        if let sensorNote = WatchCGMHost.shared.sensorNote {
            return separator + Text(sensorNote).foregroundStyle(.yellow)
        }
        return Text(verbatim: "")
    }
}

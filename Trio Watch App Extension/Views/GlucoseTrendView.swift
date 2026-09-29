import SwiftUI

struct GlucoseTrendView: View {
    let state: WatchState
    let rotationDegrees: Double
    let isWatchStateDated: Bool
    /// Advanced by the main view's timer, so the reading's age keeps counting.
    let now: Date

    /// Like the phone's home screen: the last reading stays on screen with its age until it is 12 minutes old
    /// (one missed CGM transmission, the loop's own freshness gate), even while no new data arrives.
    private static let readingDisplayLimit: TimeInterval = 12 * 60

    private var readingAge: TimeInterval? {
        state.glucoseValues.last.map { now.timeIntervalSince($0.date) }
    }

    private var isReadingShown: Bool {
        guard let readingAge = readingAge else { return false }
        return readingAge < Self.readingDisplayLimit
    }

    /// "6 m", or "< 1 m" for a reading younger than a minute, as on the phone.
    private var readingAgeText: String {
        let minutes = Int(floor((readingAge ?? 0) / 60))
        let unit = String(localized: "m", comment: "Abbreviation for Minutes")
        return minutes >= 1 ? "\(minutes)\u{00A0}\(unit)" : "<\u{00A0}1\u{00A0}\(unit)"
    }

    /// Determines the status color based on the time elapsed since the last loop
    /// - Parameter timeString: The time string representing minutes since last loop (format: "X min")
    /// - Returns: A color indicating the status:
    ///   - Green: <= 5 minutes
    ///   - Yellow: 5-10 minutes
    ///   - Red: > 10 minutes or invalid time
    private func statusColor(for timeString: String?) -> Color {
        guard let timeString = timeString,
              timeString != "--",
              let minutes = timeString.split(separator: " ").first.flatMap({ Int($0) })
        else {
            return Color.secondary
        }

        guard !isWatchStateDated else {
            return Color.secondary
        }

        switch minutes {
        case ...5:
            return Color.loopGreen
        case 5 ... 10:
            return Color.loopYellow
        case 11...:
            return Color.loopRed
        default:
            return Color.secondary
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
                    .stroke(statusColor(for: state.lastLoopTime), lineWidth: lineWidth)
                    .frame(width: circleSize, height: circleSize)
                    .background(Circle().fill(Color.bgDarkBlue))
                    .shadow(color: statusColor(for: state.lastLoopTime), radius: shadowRadius)

                TrendShape(
                    isWatchStateDated: !isReadingShown,
                    rotationDegrees: rotationDegrees,
                    deviceType: state.deviceType
                )
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)
                .shadow(color: Color.black.opacity(0.5), radius: 5)

                VStack(alignment: .center) {
                    Text(isReadingShown ? state.currentGlucose : "--")
                        .fontWeight(.semibold)
                        .font(currentGlucoseFontSize)
                        .foregroundStyle(isReadingShown ? state.currentGlucoseColorString.toColor() : Color.secondary)

                    if isReadingShown {
                        // Age and delta side by side, as in the phone's glucose bobble.
                        HStack(spacing: 4) {
                            Text(readingAgeText)
                            if let delta = state.delta {
                                Text(delta)
                            }
                        }
                        .fontWeight(.semibold)
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                    } else if state.delta != nil {
                        Text("--")
                            .fontWeight(.semibold)
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(
                isWatchStateDated ?
                    String(localized: "STALE DATA", comment: "Information displayed when watch app data outdated or stale.") :
                    state
                    .lastLoopTime ?? "--"
            )
            .font(.system(size: minutesAgoFontSize))
            .fontWidth(isWatchStateDated ? .expanded : .standard)

            Spacer()

        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

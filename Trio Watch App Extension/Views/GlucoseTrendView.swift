import SwiftUI

struct GlucoseTrendView: View {
    let state: WatchState
    let rotationDegrees: Double
    let isWatchStateDated: Bool

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

    /// A reading the G7 marked unreliable, fresh and newer than the last reliable one: shown in orange with a warning
    /// sign instead of the reliable value, as on the phone's Home.
    private var unsureReading: (date: Date, glucose: Double)? {
        guard !isWatchStateDated, let latest = state.unsureGlucoseValues.last,
              Date().timeIntervalSince(latest.date) < 12 * 60,
              latest.date > (state.glucoseValues.last?.date ?? .distantPast)
        else { return nil }
        return latest
    }

    private func formattedUnsure(_ glucose: Double) -> String {
        glucose < 40 ? String(format: "%.1f", glucose) : "\(Int(glucose.rounded()))"
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
                    isWatchStateDated: isWatchStateDated,
                    rotationDegrees: rotationDegrees,
                    deviceType: state.deviceType
                )
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)
                .shadow(color: Color.black.opacity(0.5), radius: 5)

                VStack(alignment: .center) {
                    if let unsure = unsureReading {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text(formattedUnsure(unsure.glucose))
                                .fontWeight(.semibold)
                                .font(currentGlucoseFontSize)
                                .foregroundStyle(.orange)
                        }
                        Text("Not reliable", comment: "Under a glucose value the Dexcom G7 itself marks unreliable")
                            .fontWeight(.semibold)
                            .font(.system(.caption2))
                            .foregroundStyle(.orange)
                    } else {
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    unsureReading.map {
                        Text(
                            "Glucose \(formattedUnsure($0.glucose)), not reliable: the sensor reports an issue",
                            comment: "Accessibility: a glucose value the Dexcom G7 itself marks unreliable"
                        )
                    } ?? Text(isWatchStateDated ? "--" : state.currentGlucose)
                )
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

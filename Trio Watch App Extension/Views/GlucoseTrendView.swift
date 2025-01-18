import SwiftUI

struct GlucoseTrendView: View {
    let state: WatchState
    let rotationDegrees: Double

    private var is40mm: Bool {
        let size = WKInterfaceDevice.current().screenBounds.size
        return size.height < 225 && size.width < 185
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
            return .secondary
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

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(statusColor(for: state.lastLoopTime), lineWidth: is40mm ? 1 : 1.5)
                    .frame(width: is40mm ? 86 : 105, height: is40mm ? 86 : 105)
                    .background(Circle().fill(Color.bgDarkBlue))
                    .shadow(color: statusColor(for: state.lastLoopTime), radius: is40mm ? 8 : 12)

                TrendShape(rotationDegrees: rotationDegrees, isSmallDevice: is40mm)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)
                    .shadow(color: Color.black.opacity(0.5), radius: 5)

                VStack(alignment: .center) {
                    Text(state.currentGlucose)
                        .fontWeight(.semibold)
                        .font(.system(is40mm ? .title2 : .title))
                        .foregroundStyle(state.currentGlucoseColorString.toColor())

                    if let delta = state.delta {
                        Text(delta)
                            .fontWeight(.semibold)
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(state.lastLoopTime ?? "--").font(.system(size: is40mm ? 9 : 10))

            Spacer()

        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

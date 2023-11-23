import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    private enum Config {
        static let lag: TimeInterval = 30
    }

    @Binding var suggestion: Suggestion?
    @Binding var enactedSuggestion: Suggestion?
    @Binding var closedLoop: Bool
    @Binding var timerDate: Date
    @Binding var isLooping: Bool
    @Binding var lastLoopDate: Date
    @Binding var manualTempBasal: Bool

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private let rect = CGRect(x: 0, y: 0, width: 14, height: 14)
    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Image(systemName: "circle.fill")
                    .resizable()
                    .frame(width: rect.width, height: rect.height, alignment: .center)
                    .foregroundColor(color)
                    .mask(mask(in: rect).fill(style: FillStyle(eoFill: true)))

                if isLooping {
                    ProgressView()
                        .foregroundColor(Color.loopGreen)
                }
            }
            if isLooping {
                Text("looping").font(.caption).fontWeight(.bold)
            } else if manualTempBasal {
                Text("Manual").font(.caption).fontWeight(.bold)
            } else if actualSuggestion?.timestamp != nil {
                Text(timeString).font(.caption).fontWeight(.bold)
            } else {
                Text("--").font(.caption).fontWeight(.bold)
            }
        }
    }

    private var timeString: String {
        let minAgo = Int((timerDate.timeIntervalSince(lastLoopDate) - Config.lag) / 60) + 1
        if minAgo > 1440 {
            return "--"
        }
        return "\(minAgo) " + NSLocalizedString("min", comment: "Minutes ago since last loop")
    }

    private var color: Color {
        guard actualSuggestion?.timestamp != nil else {
            return .loopGray
        }
        guard manualTempBasal == false else {
            return .loopManualTemp
        }
        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            guard actualSuggestion?.deliverAt != nil else {
                return .loopYellow
            }
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    func mask(in rect: CGRect) -> Path {
        var path = Rectangle().path(in: rect)
        if !closedLoop || manualTempBasal {
            path.addPath(Rectangle().path(in: CGRect(x: rect.minX, y: rect.midY - 5, width: rect.width, height: 10)))
        }
        return path
    }

    private var actualSuggestion: Suggestion? {
        if closedLoop, enactedSuggestion?.recieved == true {
            return enactedSuggestion ?? suggestion
        } else {
            return suggestion
        }
    }
}

extension View {
    func animateForever(
        using animation: Animation = Animation.easeInOut(duration: 1),
        autoreverses: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        let repeated = animation.repeatForever(autoreverses: autoreverses)

        return onAppear {
            withAnimation(repeated) {
                action()
            }
        }
    }
}

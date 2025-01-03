import CoreData
import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    private enum Config {
        static let lag: TimeInterval = 30
    }

    let closedLoop: Bool
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool

    let determination: [OrefDetermination]

    private let rect = CGRect(x: 0, y: 0, width: 18, height: 18)

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Image(systemName: "circle")
                    .mask(mask(in: rect).fill(style: FillStyle(eoFill: true)))
                if isLooping {
                    ProgressView()
                }
            }
            if isLooping {
                Text("looping")
            } else if manualTempBasal {
                Text("Manual")
            } else if determination.first?
                .deliverAt !=
                nil
            {
                // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
                Text(timeString)
            } else {
                Text("--")
            }
        }
        .strikethrough(!closedLoop || manualTempBasal, pattern: .solid, color: color)
        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
        .foregroundColor(color)
    }

    private var timeString: String {
        let minAgo = Int((timerDate.timeIntervalSince(lastLoopDate) - Config.lag) / 60) + 1
        if minAgo > 1440 {
            return "--"
        }
        return "\(minAgo) " + NSLocalizedString("min", comment: "Minutes ago since last loop")
    }

    private var color: Color {
        guard determination.first?.timestamp != nil
        else {
            // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
            return .secondary
        }
        guard manualTempBasal == false else {
            return .loopManualTemp
        }
        guard closedLoop == true else {
            return .secondary
        }

        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            guard determination.first?.timestamp != nil else {
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
            path.addPath(Rectangle().path(in: CGRect(x: rect.minX, y: rect.midY - 4, width: rect.width, height: 8)))
        }
        return path
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

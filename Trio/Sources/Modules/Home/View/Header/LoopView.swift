import CoreData
import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Config {
        static let lag: TimeInterval = 30
    }

    let closedLoop: Bool
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool

    let determination: [OrefDetermination]

    /// `isLooping`, but never shown for less than 2 seconds: a loop can
    /// finish in well under a second, and a pill that flickers on and off reads as a glitch
    /// rather than as work. A loop that runs longer than that ends the spin when it ends.
    @State private var showLooping: Bool = false
    @State private var spinStart: Date? = nil

    var body: some View {
        loopStatusContent
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .capsuleSpinner(isActive: showLooping, color: color)
            .task(id: isLooping) {
                if isLooping {
                    spinStart = Date()
                    showLooping = true
                } else {
                    // nothing was spinning (first run, or a stop that already elapsed)
                    guard let spinStart else {
                        showLooping = false
                        return
                    }

                    let remaining = 2 - Date().timeIntervalSince(spinStart)
                    if remaining > 0 {
                        try? await Task.sleep(for: .seconds(remaining))
                        guard !Task.isCancelled else { return }
                    }

                    showLooping = false
                    self.spinStart = nil
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(loopAccessibilityLabel))
    }

    /// Spoken description of loop state — mirrors the color/text logic so the
    /// color-coded health (green/yellow/red) is conveyed in words, not just hue.
    private var loopAccessibilityLabel: String {
        let status: String
        if manualTempBasal {
            status = String(localized: "manual temporary basal running", comment: "Accessibility: loop status")
        } else if determination.first?.timestamp == nil {
            status = String(localized: "not looping", comment: "Accessibility: loop status")
        } else if !closedLoop {
            status = String(localized: "open loop", comment: "Accessibility: loop status")
        } else {
            let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag
            if delta <= 5.minutes.timeInterval {
                status = String(localized: "looping normally", comment: "Accessibility: loop status")
            } else if delta <= 10.minutes.timeInterval {
                status = String(localized: "last loop delayed", comment: "Accessibility: loop status")
            } else {
                status = String(localized: "loop overdue", comment: "Accessibility: loop status")
            }
        }

        let age: String
        // `showLooping`, not `isLooping`: the label has to describe the pill that is on
        // screen, which keeps the looping state up for a minimum of 2 seconds.
        if showLooping {
            age = String(localized: "in progress", comment: "Accessibility: loop currently running")
        } else if determination.first?.deliverAt != nil, timeString != "--" {
            age = String(
                format: String(localized: "last loop %@", comment: "Accessibility: loop age"),
                TimeAgoFormatter.minutesAgoAccessible(from: lastLoopDate)
            )
        } else {
            age = ""
        }

        return [String(localized: "Loop", comment: "Accessibility: loop pill label"), status, age]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var loopStatusContent: some View {
        HStack(alignment: .center) {
            ZStack {
                Image(systemName: (!closedLoop || manualTempBasal) ? "circle.and.line.horizontal" : "circle")
                    .symbolEffect(.pulse, options: .repeating, isActive: showLooping && !reduceMotion)
            }
            if showLooping, reduceMotion {
                // neither the spinning border nor the pulse runs here, so say it in words
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
        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
        .foregroundColor(color)
    }

    private var timeString: String {
        let minutesAgo = TimeAgoFormatter.minutesAgoValue(from: lastLoopDate)
        if minutesAgo > 1440 {
            return "--"
        } else {
            return TimeAgoFormatter.minutesAgo(from: lastLoopDate)
        }
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
}

import CoreData
import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    @Environment(\.colorScheme) var colorScheme

    fileprivate enum Config {
        static let lag: TimeInterval = 30
    }

    let dosingMode: DosingMode
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool
    let lastGlucoseDate: Date?
    let lastPumpCommsDate: Date?
    let hasDeviceIssue: Bool

    let determination: [OrefDetermination]

    /// Fraction of the ring left open. Widens as Trio is allowed to do less.
    static func ringGap(automation: AutomationLevel, manualTempBasal: Bool) -> CGFloat {
        guard !manualTempBasal else { return 0.22 }
        switch automation {
        case .off: return 0.22
        case .hypoSuspendOnly: return 0.16
        case .reductionsOnly: return 0.1
        case .full: return 0
        }
    }

    /// Ring colour. Closed-loop freshness is meaningless when nothing is enacted, so open loop
    /// reports device health instead: green while the devices talk to Trio, red when they do not.
    static func ringColor(
        automation: AutomationLevel,
        manualTempBasal: Bool,
        hasDeviceIssue: Bool,
        hasEnactedDetermination: Bool,
        secondsSinceLastLoop: TimeInterval
    ) -> Color {
        guard !manualTempBasal else { return .loopManualTemp }
        guard automation != .off else { return hasDeviceIssue ? .loopRed : .loopGreen }
        // .timestamp only updates when reportEnacted runs
        guard hasEnactedDetermination else { return .secondary }

        let delta = secondsSinceLastLoop - Config.lag
        if delta <= 5.minutes.timeInterval {
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    private var ringGap: CGFloat {
        Self.ringGap(automation: dosingMode.automation, manualTempBasal: manualTempBasal)
    }

    /// Newest sign of life from either device, which is what freshness means when nothing is enacted.
    private var lastDeviceDate: Date? {
        [lastGlucoseDate, lastPumpCommsDate].compactMap { $0 }.max()
    }

    var body: some View {
        loopStatusWithMinutes
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.4), lineWidth: 2)
            )
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
        } else if dosingMode.automation == .off {
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
        if isLooping {
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

    private var loopStatusWithMinutes: some View {
        HStack(alignment: .center) {
            ZStack {
                Circle()
                    .trim(from: ringGap, to: 1)
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
                if isLooping {
                    ProgressView()
                }
            }
            // Open loop enacts nothing, so a "minutes since last loop" caption would imply
            // an action that never happened. The ring alone carries the state.
            if dosingMode.automation != .off {
                if isLooping {
                    Text("looping")
                } else if manualTempBasal {
                    Text("Manual")
                } else if determination.first?.deliverAt != nil {
                    // .timestamp only updates when reportEnacted runs, so key the caption off deliverAt
                    Text(timeString)
                } else {
                    Text("--")
                }
            }
        }
        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
        .foregroundColor(color)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        guard dosingMode.automation == .off else {
            return Text("\(dosingMode.displayName), last loop \(timeString)")
        }
        guard let lastDeviceDate else {
            return Text("\(dosingMode.displayName), no recent device communication")
        }
        return Text("\(dosingMode.displayName), last device communication \(TimeAgoFormatter.minutesAgo(from: lastDeviceDate))")
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
        Self.ringColor(
            automation: dosingMode.automation,
            manualTempBasal: manualTempBasal,
            hasDeviceIssue: hasDeviceIssue,
            hasEnactedDetermination: determination.first?.timestamp != nil,
            secondsSinceLastLoop: timerDate.timeIntervalSince(lastLoopDate)
        )
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

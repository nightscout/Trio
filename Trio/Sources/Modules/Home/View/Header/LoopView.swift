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

    /// Fraction of the ring removed at *each* of the two horizontal gaps (3 and 9 o'clock),
    /// leaving a top and a bottom arc. Anything short of full automation reads as an open ring;
    /// the centre symbol says why.
    static let openRingGap: CGFloat = 0.12

    static func ringGap(automation: AutomationLevel, manualTempBasal: Bool) -> CGFloat {
        guard !manualTempBasal else { return openRingGap }
        return automation == .full ? 0 : openRingGap
    }

    /// Symbol inside the ring for the modes that still dose, but only under a constraint.
    static func centerSymbol(automation: AutomationLevel) -> String? {
        switch automation {
        case .reductionsOnly:
            return "hand.raised.fill"
        case .hypoSuspendOnly:
            return "hand.pinch.fill"
        case .full,
             .off:
            return nil
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

    private var centerSymbol: String? {
        manualTempBasal ? nil : Self.centerSymbol(automation: dosingMode.automation)
    }

    /// Newest sign of life from either device, which is what freshness means when nothing is enacted.
    private var lastDeviceDate: Date? {
        [lastGlucoseDate, lastPumpCommsDate].compactMap { $0 }.max()
    }

    /// Only full automation carries a "last loop" caption. The constrained modes drop it and show
    /// the bare ring; their freshness still comes through in the ring colour.
    static func showsCaption(automation: AutomationLevel) -> Bool { automation == .full }

    private var showsCaption: Bool { Self.showsCaption(automation: dosingMode.automation) }

    @ViewBuilder var body: some View {
        if showsCaption {
            loopStatus
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.4), lineWidth: 2)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(loopAccessibilityLabel))
        } else {
            // No caption to enclose, so the capsule would frame empty space. The ring stands alone,
            // drawn larger to hold the same visual weight.
            loopStatus
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(loopAccessibilityLabel))
        }
    }

    /// Spoken description of loop state — mirrors the color/text logic so the
    /// color-coded health (green/yellow/red) is conveyed in words, not just hue.
    private var loopAccessibilityLabel: String {
        let status: String
        if manualTempBasal {
            status = String(localized: "manual temporary basal running", comment: "Accessibility: loop status")
        } else if dosingMode.automation == .off {
            // checked before the determination, which never carries a timestamp in open loop
            status = String(localized: "not dosing", comment: "Accessibility: loop status")
        } else if determination.first?.timestamp == nil {
            status = String(localized: "not looping", comment: "Accessibility: loop status")
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
        } else if dosingMode.automation == .off {
            // loop age says nothing when nothing is enacted; report device contact instead
            age = lastDeviceDate.map {
                String(
                    format: String(localized: "last device communication %@", comment: "Accessibility: device age"),
                    TimeAgoFormatter.minutesAgoAccessible(from: $0)
                )
            } ?? ""
        } else if determination.first?.deliverAt != nil, timeString != "--" {
            age = String(
                format: String(localized: "last loop %@", comment: "Accessibility: loop age"),
                TimeAgoFormatter.minutesAgoAccessible(from: lastLoopDate)
            )
        } else {
            age = ""
        }

        return [dosingMode.displayName, status, age]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    // @ScaledMetric so the ring grows with the user's text size; a fixed point size would leave
    // it unreadable for anyone relying on larger type.
    @ScaledMetric(relativeTo: .callout) private var compactRingDiameter: CGFloat = 18
    @ScaledMetric(relativeTo: .callout) private var expandedRingDiameter: CGFloat = 32

    private var ringDiameter: CGFloat { showsCaption ? compactRingDiameter : expandedRingDiameter }
    private var ringLineWidth: CGFloat { max(2, ringDiameter * 0.08) }

    private var loopStatus: some View {
        HStack(alignment: .center) {
            ZStack {
                // A manual temp basal blocks enactment, so closed loop does not get a closed ring.
                if dosingMode == .closed, !manualTempBasal {
                    Image(systemName: "circle")
                } else {
                    Circle()
                        .trim(from: ringGap / 2, to: 0.5 - ringGap / 2)
                        .stroke(style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                    Circle()
                        .trim(from: 0.5 + ringGap / 2, to: 1 - ringGap / 2)
                        .stroke(style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                }
                if isLooping {
                    ProgressView()
                } else if let centerSymbol {
                    Image(systemName: centerSymbol)
                        .font(.system(size: ringDiameter * 0.44, weight: .semibold))
                }
            }
            .frame(width: ringDiameter, height: ringDiameter)
            // A caption would imply an action that did not happen in open loop, and overstates what
            // the constrained modes do. The ring carries the state instead.
            if showsCaption {
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

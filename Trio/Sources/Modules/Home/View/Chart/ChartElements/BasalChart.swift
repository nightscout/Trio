import Charts
import Foundation
import SwiftUI

struct BasalProfile: Hashable {
    let amount: Double
    var isOverwritten: Bool
    let startDate: Date
    let endDate: Date?
    init(amount: Double, isOverwritten: Bool, startDate: Date, endDate: Date? = nil) {
        self.amount = amount
        self.isOverwritten = isOverwritten
        self.startDate = startDate
        self.endDate = endDate
    }
}

extension MainChartCanvas {
    var basalChart: some View {
        VStack {
            Chart {
                drawCurrentTimeMarker()
                drawTempBasals()
                drawBasalProfile()
                drawSuspensions()
            }.onChange(of: state.tempBasals) {
                calculateBasals()
                calculateTempBasals()
            }
            .onChange(of: state.maxBasal) {
                calculateBasals()
            }
            .frame(width: canvasWidth, height: basalHeight)
            .chartXScale(domain: windowStart ... windowEnd)
            .chartXAxis { mainChartXAxis } // grid lines only; hour labels render once, on the bottom pane
            .chartYAxis(.hidden)
            .chartYScale(domain: 0 ... basalDomainMax)
        }
    }

    /// Upper bound of the basal chart's y-domain. The bars hang from the top of the plot
    /// (drawn at `basalDomainMax - rate`), so the tallest rate spans the full strip height —
    /// matching the old rendering, which achieved the same look by rotating and mirroring
    /// the plot content.
    var basalDomainMax: Double {
        let tempMax = preparedTempBasals.map(\.rate).max() ?? 0
        let profileMax = basalProfiles.map(\.amount).max() ?? 0
        return max(tempMax, profileMax, 0.1)
    }

    /// Converts a basal rate to its top-anchored y value.
    private func invertedY(_ rate: Double) -> Double {
        basalDomainMax - rate
    }
}

// MARK: - Draw functions

extension MainChartCanvas {
    func drawTempBasals() -> some ChartContent {
        // only bars overlapping the render window; the rest clip invisibly but still cost layout
        let visible = preparedTempBasals.filter { $0.end >= windowStart && $0.start <= windowEnd }
        return ForEach(visible, id: \.start) { basal in
            RectangleMark(
                xStart: .value("start", basal.start),
                xEnd: .value("end", basal.end),
                yStart: .value("rate-start", basalDomainMax),
                yEnd: .value("rate-end", invertedY(basal.rate))
            ).foregroundStyle(
                .linearGradient(
                    colors: [
                        Color.insulin.opacity(0.6),
                        Color.insulin.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            ).alignsMarkStylesWithPlotArea()
                .opacity(basal.isScheduled ? 0.5 : 1)

            LineMark(x: .value("Start Date", basal.start), y: .value("Amount", invertedY(basal.rate)))
                .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                .opacity(basal.isScheduled ? 0.5 : 1)

            LineMark(x: .value("End Date", basal.end), y: .value("Amount", invertedY(basal.rate)))
                .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                .opacity(basal.isScheduled ? 0.5 : 1)
        }
    }

    func drawBasalProfile() -> some ChartContent {
        /// dashed profile line
        let visible = basalProfiles.filter { ($0.endDate ?? state.endMarker) >= windowStart && $0.startDate <= windowEnd }
        return ForEach(visible, id: \.self) { profile in
            LineMark(
                x: .value("Start Date", profile.startDate),
                y: .value("Amount", invertedY(profile.amount)),
                series: .value("profile", "profile")
            ).lineStyle(.init(lineWidth: 2, dash: [2, 4])).foregroundStyle(Color.insulin)
            LineMark(
                x: .value("End Date", profile.endDate ?? state.endMarker),
                y: .value("Amount", invertedY(profile.amount)),
                series: .value("profile", "profile")
            ).lineStyle(.init(lineWidth: 2.5, dash: [2, 4])).foregroundStyle(Color.insulin)
        }
    }

    /// Suspend→resume intervals resolved once, so the mark loop does no per-mark lookups.
    private func suspensionIntervals() -> [(start: Date, end: Date, height: Double)] {
        let suspensions = state.suspendAndResumeEvents
        let now = Date()
        var intervals = [(start: Date, end: Date, height: Double)]()

        for suspension in suspensions {
            guard suspension.type == EventType.pumpSuspend.rawValue, let suspensionStart = suspension.timestamp else {
                continue
            }
            let suspensionEnd = min(
                suspensions.first(where: {
                    $0.timestamp ?? now > suspensionStart && $0.type == EventType.pumpResume.rawValue
                })?.timestamp ?? now,
                now
            )
            let basalProfileDuringSuspension = basalProfiles.first(where: { $0.startDate <= suspensionStart })
            // Clamp to the explicit y-domain: the fallback height of 1 U/hr can exceed
            // `basalDomainMax` when no profile data is available, and unlike the old
            // auto-scaled (flipped) plot, an explicit domain would clip the mark.
            let height = min(basalProfileDuringSuspension?.amount ?? 1, basalDomainMax)
            intervals.append((suspensionStart, suspensionEnd, height))
        }
        return intervals
    }

    func drawSuspensions() -> some ChartContent {
        let visible = suspensionIntervals().filter { $0.end >= windowStart && $0.start <= windowEnd }
        return ForEach(visible, id: \.start) { interval in
            RectangleMark(
                xStart: .value("start", interval.start),
                xEnd: .value("end", interval.end),
                yStart: .value("suspend-start", basalDomainMax),
                yEnd: .value("suspend-end", invertedY(interval.height))
            )
            .foregroundStyle(Color.loopGray.opacity(colorScheme == .dark ? 0.3 : 0.8))
        }
    }
}

// MARK: - Calculation

extension MainChartCanvas {
    @MainActor func calculateTempBasals() {
        let now = Date()
        let suspensionTimes = state.suspendAndResumeEvents.compactMap(\.timestamp)

        // Snapshot the managed-object fields once; plain values from here on.
        let events = state.tempBasals.map {
            (
                timestamp: $0.timestamp,
                duration: $0.tempBasal?.duration ?? 0,
                rate: $0.tempBasal?.rate,
                isScheduled: $0.tempBasal?.isScheduledBasal ?? false
            )
        }

        var prepared = [(start: Date, end: Date, rate: Double, isScheduled: Bool)]()
        prepared.reserveCapacity(events.count)

        for (index, event) in events.enumerated() {
            let timestamp = event.timestamp ?? now
            let end = timestamp + event.duration.minutes
            let isInsulinSuspended = suspensionTimes.contains { $0 >= timestamp && $0 <= end }
            let rate = Double(truncating: event.rate ?? 0) * (isInsulinSuspended ? 0 : 1)

            // pump-reported scheduled basal carries exact bounds; no clipping
            if event.isScheduled {
                prepared.append((timestamp, end, rate, true))
                continue
            }

            // A bar ends where the next later-starting temp basal begins,
            // else at its own scheduled end.
            var next = index + 1
            while next < events.count {
                if let nextStart = events[next].timestamp, nextStart > timestamp { break }
                next += 1
            }
            if next < events.count, let nextStart = events[next].timestamp {
                prepared.append((timestamp, nextStart, rate, false))
            } else {
                prepared.append((timestamp, end, rate, false))
            }
        }

        // gaps no event covers ran the pump's schedule; inferred in memory, drawn dimmed
        var timeline = events.map {
            ScheduledBasalInference.TimelineEvent(
                start: $0.timestamp ?? now,
                end: ($0.timestamp ?? now) + $0.duration.minutes,
                kind: .tempBasal
            )
        }
        timeline += state.suspendAndResumeEvents.compactMap { event -> ScheduledBasalInference.TimelineEvent? in
            guard let timestamp = event.timestamp else { return nil }
            let isSuspend = event.type == PumpEventStored.EventType.pumpSuspend.rawValue
            return ScheduledBasalInference.TimelineEvent(start: timestamp, kind: isSuspend ? .suspend : .resume)
        }
        for segment in ScheduledBasalInference.segments(events: timeline, profile: state.basalProfile, now: now) {
            prepared.append((segment.start, segment.end, Double(truncating: segment.rate as NSNumber), true))
        }

        preparedTempBasals = prepared
    }

    func findRegularBasalPoints(
        timeBegin: TimeInterval,
        timeEnd: TimeInterval
    ) async -> [BasalProfile] {
        guard timeBegin < timeEnd else { return [] }

        let beginDate = Date(timeIntervalSince1970: timeBegin)
        let startOfDay = Calendar.current.startOfDay(for: beginDate)
        let profile = state.basalProfile
        var basalPoints: [BasalProfile] = []
        var lastEntryBeforeRange: (amount: Double, date: Date)?

        // Iterate over the next three days, multiplying the time intervals
        for dayOffset in 0 ..< 3 {
            let dayTimeOffset = TimeInterval(dayOffset * 24 * 60 * 60) // One Day in seconds
            for entry in profile {
                let basalTime = startOfDay.addingTimeInterval(entry.minutes.minutes.timeInterval + dayTimeOffset)
                let basalTimeInterval = basalTime.timeIntervalSince1970

                if basalTimeInterval < timeBegin {
                    // Track the last profile entry before the visible range
                    if lastEntryBeforeRange == nil || basalTime > lastEntryBeforeRange!.date {
                        lastEntryBeforeRange = (amount: Double(entry.rate), date: basalTime)
                    }
                } else if basalTimeInterval < timeEnd {
                    basalPoints.append(BasalProfile(
                        amount: Double(entry.rate),
                        isOverwritten: false,
                        startDate: basalTime
                    ))
                }
            }
        }

        // Include the active profile entry at timeBegin so the line starts at the chart's left edge
        if let lastBefore = lastEntryBeforeRange {
            basalPoints.append(BasalProfile(
                amount: lastBefore.amount,
                isOverwritten: false,
                startDate: beginDate
            ))
        }

        return basalPoints
    }

    func calculateBasals() {
        Task {
            let dayAgoTime = Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970

            async let getRegularBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: state.endMarker.timeIntervalSince1970
            )

            var regularPoints = await getRegularBasalPoints
            regularPoints.sort { $0.startDate < $1.startDate }

            var basals: [BasalProfile] = []

            // No basal data? Then there's nothing to draw
            if regularPoints.isEmpty {
                // basals stays empty; do nothing
            }
            // Exactly one data point?
            else if regularPoints.count == 1 {
                let single = regularPoints[0]
                // Make one BasalProfile that stretches entire marker area
                basals.append(
                    BasalProfile(
                        amount: single.amount,
                        isOverwritten: single.isOverwritten,
                        startDate: state.startMarker,
                        endDate: state.endMarker
                    )
                )
            }
            // Multiple data points: chain them so each point ends where the next begins
            else {
                for i in 0 ..< (regularPoints.count - 1) {
                    basals.append(
                        BasalProfile(
                            amount: regularPoints[i].amount,
                            isOverwritten: regularPoints[i].isOverwritten,
                            startDate: regularPoints[i].startDate,
                            endDate: regularPoints[i + 1].startDate
                        )
                    )
                }
                // The last item goes from its start to endMarker
                if let lastItem = regularPoints.last {
                    basals.append(
                        BasalProfile(
                            amount: lastItem.amount,
                            isOverwritten: lastItem.isOverwritten,
                            startDate: lastItem.startDate,
                            endDate: state.endMarker
                        )
                    )
                }
            }

            await MainActor.run {
                basalProfiles = basals
            }
        }
    }
}

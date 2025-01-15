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

extension MainChartView {
    var basalChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()
                drawTempBasals(dummy: false)
                drawBasalProfile()
                drawSuspensions()
            }.onChange(of: state.tempBasals) {
                calculateBasals()
                calculateTempBasalsInBackground()
            }
            .onChange(of: state.maxBasal) {
                calculateBasals()
            }
            .frame(minHeight: geo.size.height * 0.05)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: state.startMarker ... state.endMarker)
            .chartXAxis { basalChartXAxis }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { basalChartPlotStyle($0) }
        }
    }
}

// MARK: - Draw functions

extension MainChartView {
    func drawTempBasals(dummy: Bool) -> some ChartContent {
        ForEach(preparedTempBasals, id: \.rate) { basal in
            if dummy {
                RectangleMark(
                    xStart: .value("start", basal.start),
                    xEnd: .value("end", basal.end),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", basal.rate)
                ).foregroundStyle(Color.clear)

                LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.clear)

                LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.clear)
            } else {
                RectangleMark(
                    xStart: .value("start", basal.start),
                    xEnd: .value("end", basal.end),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", basal.rate)
                ).foregroundStyle(
                    .linearGradient(
                        colors: [
                            Color.insulin.opacity(0.6),
                            Color.insulin.opacity(0.1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                ).alignsMarkStylesWithPlotArea()

                LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
            }
        }
    }

    func drawBasalProfile() -> some ChartContent {
        /// dashed profile line
        ForEach(basalProfiles, id: \.self) { profile in
            LineMark(
                x: .value("Start Date", profile.startDate),
                y: .value("Amount", profile.amount),
                series: .value("profile", "profile")
            ).lineStyle(.init(lineWidth: 2, dash: [2, 4])).foregroundStyle(Color.insulin)
            LineMark(
                x: .value("End Date", profile.endDate ?? state.endMarker),
                y: .value("Amount", profile.amount),
                series: .value("profile", "profile")
            ).lineStyle(.init(lineWidth: 2.5, dash: [2, 4])).foregroundStyle(Color.insulin)
        }
    }

    func drawSuspensions() -> some ChartContent {
        let suspensions = state.suspensions
        return ForEach(suspensions) { suspension in
            let now = Date()

            if let type = suspension.type, type == EventType.pumpSuspend.rawValue, let suspensionStart = suspension.timestamp {
                let suspensionEnd = min(
                    (
                        suspensions
                            .first(where: {
                                $0.timestamp ?? now > suspensionStart && $0.type == EventType.pumpResume.rawValue })?
                            .timestamp
                    ) ?? now,
                    now
                )

                let basalProfileDuringSuspension = basalProfiles.first(where: { $0.startDate <= suspensionStart })
                let suspensionMarkHeight = basalProfileDuringSuspension?.amount ?? 1

                RectangleMark(
                    xStart: .value("start", suspensionStart),
                    xEnd: .value("end", suspensionEnd),
                    yStart: .value("suspend-start", 0),
                    yEnd: .value("suspend-end", suspensionMarkHeight)
                )
                .foregroundStyle(Color.loopGray.opacity(colorScheme == .dark ? 0.3 : 0.8))
            }
        }
    }
}

// MARK: - Calculation

extension MainChartView {
    func calculateTempBasalsInBackground() {
        Task {
            let basals = await prepareTempBasals()
            await MainActor.run {
                preparedTempBasals = basals
            }
        }
    }

    func prepareTempBasals() async -> [(start: Date, end: Date, rate: Double)] {
        let now = Date()
        let tempBasals = state.tempBasals

        return tempBasals.compactMap { temp -> (start: Date, end: Date, rate: Double)? in
            let duration = temp.tempBasal?.duration ?? 0
            let timestamp = temp.timestamp ?? Date()
            let end = timestamp + duration.minutes
            let isInsulinSuspended = state.suspensions.contains { $0.timestamp ?? now >= timestamp && $0.timestamp ?? now <= end }

            let rate = Double(truncating: temp.tempBasal?.rate ?? Decimal.zero as NSDecimalNumber) * (isInsulinSuspended ? 0 : 1)

            // Check if there's a subsequent temp basal to determine the end time
            guard let nextTemp = state.tempBasals.first(where: { $0.timestamp ?? .distantPast > timestamp }) else {
                return (timestamp, end, rate)
            }
            return (timestamp, nextTemp.timestamp ?? Date(), rate)
        }
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

        // Iterate over the next three days, multiplying the time intervals
        for dayOffset in 0 ..< 3 {
            let dayTimeOffset = TimeInterval(dayOffset * 24 * 60 * 60) // One Day in seconds
            for entry in profile {
                let basalTime = startOfDay.addingTimeInterval(entry.minutes.minutes.timeInterval + dayTimeOffset)
                let basalTimeInterval = basalTime.timeIntervalSince1970

                // Only append points within the timeBegin and timeEnd range
                if basalTimeInterval >= timeBegin, basalTimeInterval < timeEnd {
                    basalPoints.append(BasalProfile(
                        amount: Double(entry.rate),
                        isOverwritten: false,
                        startDate: basalTime
                    ))
                }
            }
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
